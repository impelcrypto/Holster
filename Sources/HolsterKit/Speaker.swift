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
            if let data = await fetchAudio(text: text, config: config) {
                // A newer speak()/stop() may have superseded this task mid-fetch.
                guard !Task.isCancelled, let player = try? AVAudioPlayer(data: data) else { return }
                self.player = player
                player.play()
                return
            }
            guard !Task.isCancelled else { return }
            speakBuiltIn(text, voice: config?.voice)
        }
    }

    /// nil when no remote provider is configured, or on any fetch failure — the
    /// caller then falls back to the built-in macOS voice.
    private func fetchAudio(text: String, config: TTSConfig?) async -> Data? {
        guard let config else { return nil }
        do {
            if config.provider == "edge" {
                return try await EdgeTTS.synthesize(text: text, voice: config.voice ?? EdgeTTS.defaultVoice)
            }
            if let baseURL = config.baseURL, !baseURL.isEmpty {
                return try await fetchOpenAI(text: text, baseURL: baseURL, config: config)
            }
        } catch {
            // Fall through to the built-in voice.
        }
        return nil
    }

    public func stop() {
        task?.cancel()
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speakBuiltIn(_ text: String, voice: String?) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Speaker.resolveVoice(voice) ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    /// Accepts a voice identifier (com.apple.voice.premium.en-US.Ava) or a name
    /// ("Ava", also matching "Ava (Premium)"); name ties pick the highest quality.
    nonisolated static func resolveVoice(_ name: String?) -> AVSpeechSynthesisVoice? {
        guard let name, !name.isEmpty else { return nil }
        if let voice = AVSpeechSynthesisVoice(identifier: name) { return voice }
        let lowered = name.lowercased()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.name.lowercased() == lowered || $0.name.lowercased().hasPrefix(lowered + " (") }
            .max { $0.quality.rawValue < $1.quality.rawValue }
    }

    private func fetchOpenAI(text: String, baseURL: String, config: TTSConfig) async throws -> Data {
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
