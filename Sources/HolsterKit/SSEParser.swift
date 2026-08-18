import Foundation

/// Line-level parser for OpenAI-style chat completion SSE streams.
/// Deliberately tolerant: proxies (CLIProxyAPI etc.) are known to emit
/// comments, blank lines, and occasionally malformed chunks mid-stream.
public enum SSEParser {
    public enum Event: Equatable {
        case delta(String)
        /// Hidden thinking (reasoning_content); proves the stream is alive
        /// even though there is nothing to display yet.
        case reasoning
        case done
        case error(String)
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let reasoningContent: String?

                enum CodingKeys: String, CodingKey {
                    case content
                    case reasoningContent = "reasoning_content"
                }
            }
            let delta: Delta?
        }
        struct APIError: Decodable { let message: String? }
        let choices: [Choice]?
        let error: APIError?
    }

    /// nil means "nothing useful on this line, keep reading".
    public static func parseLine(_ line: String) -> Event? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data)
        else { return nil }
        if let error = chunk.error {
            return .error(error.message ?? "Unknown API error")
        }
        if let content = chunk.choices?.first?.delta?.content, !content.isEmpty {
            return .delta(content)
        }
        if let thinking = chunk.choices?.first?.delta?.reasoningContent, !thinking.isEmpty {
            return .reasoning
        }
        return nil
    }
}
