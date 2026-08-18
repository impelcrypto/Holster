import AVFoundation
import Foundation

/// Text-to-speech: OpenAI-compatible /audio/speech when configured, otherwise
/// (or on failure) the built-in macOS voice.
@MainActor
public final class Speaker {
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var task: Task<Void, Never>?

    public init() {}

    public func speak(_ text: String, config: TTSConfig?) {
        stop()
        task = Task {
            if let config, let baseURL = config.baseURL, !baseURL.isEmpty {
                do {
                    let data = try await fetchAudio(text: text, baseURL: baseURL, config: config)
                    player = try AVAudioPlayer(data: data)
                    player?.play()
                    return
                } catch {
                    // Fall through to the built-in voice.
                }
            }
            speakBuiltIn(text)
        }
    }

    public func stop() {
        task?.cancel()
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speakBuiltIn(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    private func fetchAudio(text: String, baseURL: String, config: TTSConfig) async throws -> Data {
        struct Body: Encodable {
            let model: String
            let voice: String
            let input: String
            let response_format: String
        }
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: "\(base)/audio/speech") else {
            throw LLMError.badURL(baseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = config.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(Body(
            model: config.model ?? "gpt-4o-mini-tts",
            voice: config.voice ?? "alloy",
            input: text,
            response_format: "mp3"))
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LLMError.http(http.statusCode, String(decoding: data.prefix(400), as: UTF8.self))
        }
        return data
    }
}
