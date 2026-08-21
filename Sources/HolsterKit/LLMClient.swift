import Foundation

public struct LLMRequest {
    public var baseURL: String
    public var apiKey: String?
    public var model: String
    public var prompt: String
    /// "low" / "medium" / "high"; nil omits the field entirely — some
    /// OpenAI-compatible endpoints reject it for non-reasoning models.
    public var reasoningEffort: String?
    public var stream: Bool

    public init(
        baseURL: String,
        apiKey: String? = nil,
        model: String,
        prompt: String,
        reasoningEffort: String? = nil,
        stream: Bool = true
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.prompt = prompt
        self.reasoningEffort = reasoningEffort
        self.stream = stream
    }
}

public enum LLMError: LocalizedError {
    case badURL(String)
    case http(Int, String)
    case api(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .badURL(let url): return "Invalid base_url: \(url)"
        case .http(let status, let body):
            let detail = body.prefix(400)
            return "HTTP \(status)\(detail.isEmpty ? "" : ": \(detail)")"
        case .api(let message): return message
        case .emptyResponse: return "The model returned an empty response"
        }
    }
}

public enum LLMEvent: Equatable {
    /// Hidden thinking is arriving; nothing to display yet, but the stream
    /// is alive (reasoning models emit this before any content).
    case reasoning
    case content(String)
    /// The primary provider failed; subsequent events come from the fallback.
    case fallback
}

public enum LLMClient {
    /// Yields content deltas. With request.stream == false, yields the full
    /// text once — callers treat both modes identically.
    public static func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if request.stream {
                        try await streamSSE(request, into: continuation)
                    } else {
                        continuation.yield(.content(try await completeOnce(request)))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// ANY pre-content failure (401, bad URL, empty response, ...) yields .fallback
    /// and retries once; after content, errors propagate — no duplicated output.
    public static func streamWithFallback(
        _ request: LLMRequest,
        fallback: LLMRequest?
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var sawContent = false
                do {
                    do {
                        for try await event in stream(request) {
                            if case .content = event { sawContent = true }
                            continuation.yield(event)
                        }
                    } catch let error {
                        guard let fallback, !sawContent, !Task.isCancelled else { throw error }
                        continuation.yield(.fallback)
                        for try await event in stream(fallback) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static func completeOnce(_ request: LLMRequest) async throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message?
            }
            let choices: [Choice]?
        }
        let urlRequest = try makeChatRequest(request)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try checkStatus(response, data: data)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices?.first?.message?.content, !content.isEmpty else {
            throw LLMError.emptyResponse
        }
        return content
    }

    public static func listModels(baseURL: String, apiKey: String?) async throws -> [String] {
        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let url = endpoint(baseURL, path: "models") else { throw LLMError.badURL(baseURL) }
        var urlRequest = URLRequest(url: url)
        applyAuth(&urlRequest, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try checkStatus(response, data: data)
        return try JSONDecoder().decode(Response.self, from: data).data.map(\.id).sorted()
    }

    // MARK: - Internals

    private static func streamSSE(
        _ request: LLMRequest,
        into continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation
    ) async throws {
        let urlRequest = try makeChatRequest(request)
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var body = ""
            // `where` would only skip appends while the server keeps the
            // connection open; break so an unclosed error response can't hang.
            for try await line in bytes.lines {
                body += line
                if body.count >= 2000 { break }
            }
            throw LLMError.http(http.statusCode, body)
        }
        var sawContent = false
        for try await line in bytes.lines {
            switch SSEParser.parseLine(line) {
            case .delta(let text):
                sawContent = true
                continuation.yield(.content(text))
            case .reasoning:
                continuation.yield(.reasoning)
            case .error(let message):
                throw LLMError.api(message)
            case .done:
                if !sawContent { throw LLMError.emptyResponse }
                return
            case nil:
                continue
            }
        }
        // Stream ended without [DONE]; fine as long as content arrived.
        if !sawContent { throw LLMError.emptyResponse }
    }

    private static func makeChatRequest(_ request: LLMRequest) throws -> URLRequest {
        struct Body: Encodable {
            struct Message: Encodable {
                let role: String
                let content: String
            }
            let model: String
            let messages: [Message]
            let stream: Bool
            let reasoningEffort: String?

            enum CodingKeys: String, CodingKey {
                case model, messages, stream
                case reasoningEffort = "reasoning_effort"
            }
        }
        guard let url = endpoint(request.baseURL, path: "chat/completions") else {
            throw LLMError.badURL(request.baseURL)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 300
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&urlRequest, apiKey: request.apiKey)
        urlRequest.httpBody = try JSONEncoder().encode(Body(
            model: request.model,
            messages: [.init(role: "user", content: request.prompt)],
            stream: request.stream,
            reasoningEffort: request.reasoningEffort))
        return urlRequest
    }

    private static func endpoint(_ baseURL: String, path: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: "\(base)/\(path)")
    }

    private static func applyAuth(_ request: inout URLRequest, apiKey: String?) {
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode != 200 else { return }
        throw LLMError.http(http.statusCode, String(decoding: data, as: UTF8.self))
    }
}
