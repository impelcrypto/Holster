import CryptoKit
import Foundation

struct EdgeTTSError: Error { let message: String }

struct EdgeVoice: Identifiable, Hashable {
    let shortName: String    // e.g. en-US-AvaMultilingualNeural
    let locale: String       // e.g. en-US
    let gender: String       // Female / Male
    var id: String { shortName }
}

/// Unofficial Microsoft Edge read-aloud TTS over WebSocket: free, no API key.
/// May break if Microsoft changes the endpoint, so callers must fall back.
enum EdgeTTS {
    static let defaultVoice = "en-US-AvaMultilingualNeural"

    private static let trustedToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private static let secGecVersion = "1-143.0.3650.75"
    private static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0"

    static func listVoices() async throws -> [EdgeVoice] {
        var comps = URLComponents(string:
            "https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/voices/list")!
        comps.queryItems = [
            .init(name: "trustedclienttoken", value: trustedToken),
            .init(name: "Sec-MS-GEC", value: secMsGec()),
            .init(name: "Sec-MS-GEC-Version", value: secGecVersion),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw EdgeTTSError(message: "voices list HTTP \(http.statusCode)")
        }
        struct Raw: Decodable {
            let shortName: String, locale: String, gender: String
            enum CodingKeys: String, CodingKey {
                case shortName = "ShortName", locale = "Locale", gender = "Gender"
            }
        }
        return try JSONDecoder().decode([Raw].self, from: data).map {
            EdgeVoice(shortName: $0.shortName, locale: $0.locale, gender: $0.gender)
        }
    }

    static func synthesize(text: String, voice: String) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await stream(text: text, voice: voice) }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw EdgeTTSError(message: "timeout")
            }
            let data = try await group.next()!
            group.cancelAll()
            return data
        }
    }

    private static func stream(text: String, voice: String) async throws -> Data {
        let connectionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var comps = URLComponents(string:
            "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1")!
        comps.queryItems = [
            .init(name: "TrustedClientToken", value: trustedToken),
            .init(name: "ConnectionId", value: connectionId),
            .init(name: "Sec-MS-GEC", value: secMsGec()),
            .init(name: "Sec-MS-GEC-Version", value: secGecVersion),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")

        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        try await task.send(.string(speechConfigMessage()))
        try await task.send(.string(ssmlMessage(requestId: connectionId, text: text, voice: voice)))

        var audio = Data()
        while true {
            switch try await task.receive() {
            case .string(let s):
                if s.contains("Path:turn.end") { return audio }
            case .data(let d):
                if let chunk = audioChunk(d) { audio.append(chunk) }
            @unknown default:
                break
            }
        }
    }

    /// Binary frame: 2-byte big-endian header length, header text, then mp3 bytes.
    private static func audioChunk(_ d: Data) -> Data? {
        guard d.count >= 2 else { return nil }
        let headerLen = Int(d[d.startIndex]) << 8 | Int(d[d.startIndex + 1])
        let audioStart = d.startIndex + 2 + headerLen
        guard audioStart <= d.endIndex else { return nil }
        let header = String(decoding: d[(d.startIndex + 2)..<audioStart], as: UTF8.self)
        guard header.contains("Path:audio") else { return nil }
        return d[audioStart..<d.endIndex]
    }

    /// Sec-MS-GEC DRM token: Windows-epoch ticks rounded to 5 min, SHA256 upper.
    private static func secMsGec() -> String {
        var ticks = Date().timeIntervalSince1970 + 11_644_473_600
        ticks -= ticks.truncatingRemainder(dividingBy: 300)
        ticks *= 1e7
        let digest = SHA256.hash(data: Data((String(format: "%.0f", ticks) + trustedToken).utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    private static func speechConfigMessage() -> String {
        "X-Timestamp:\(timestamp())\r\n"
            + "Content-Type:application/json; charset=utf-8\r\n"
            + "Path:speech.config\r\n\r\n"
            + #"{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}"#
            + "\r\n"
    }

    private static func ssmlMessage(requestId: String, text: String, voice: String) -> String {
        let ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
            + "<voice name='\(voice)'><prosody pitch='+0Hz' rate='+0%' volume='+0%'>"
            + escapeXML(text) + "</prosody></voice></speak>"
        return "X-RequestId:\(requestId)\r\n"
            + "Content-Type:application/ssml+xml\r\n"
            + "X-Timestamp:\(timestamp())Z\r\n"
            + "Path:ssml\r\n\r\n"
            + ssml
    }

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return f.string(from: Date())
    }
}
