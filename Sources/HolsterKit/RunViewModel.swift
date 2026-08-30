import AppKit
import Foundation

@MainActor
public final class RunViewModel: ObservableObject {
    public enum State: Equatable {
        case capturing
        case streaming
        case done
        case failed(String)
    }

    @Published public private(set) var markdown = ""
    @Published public private(set) var state: State = .capturing
    @Published public private(set) var toast: String?
    /// Hidden thinking is arriving but no visible content yet.
    @Published public private(set) var isReasoning = false
    /// Text the user has highlighted in the result; Speak targets this.
    @Published public private(set) var selectedText = ""

    public let commandName: String
    /// Switches to the fallback model name when the primary provider fails.
    @Published public private(set) var modelName: String

    /// The captured selection; retry reuses it.
    public var selection: String?

    public var onRetry: (() -> Void)?
    public var onSpeak: ((String) -> Void)?
    public var onCopied: (() -> Void)?
    public var onStop: (() -> Void)?

    private let copyOnSelect: Bool
    private var accumulated = ""
    private var flushScheduled = false
    private var toastTask: Task<Void, Never>?
    private var autoCopyTask: Task<Void, Never>?

    /// Overridden in tests so they never clobber the real clipboard.
    var writeToPasteboard: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public func flashToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    public init(command: CommandConfig) {
        commandName = command.name
        modelName = command.model
        copyOnSelect = command.wantsCopyOnSelect
    }

    public func beginStreaming() {
        state = .streaming
    }

    public func noteReasoning() {
        if !isReasoning { isReasoning = true }
    }

    public func noteFallback(providerName: String, model: String) {
        modelName = model
        isReasoning = false
        flashToast("Provider failed — using \(providerName)")
    }

    /// Keeps the last non-empty selection: clicking Speak resigns the field
    /// editor (an empty-selection event) just before the button action reads it.
    public func setSelectedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed != selectedText { selectedText = trimmed }
        if copyOnSelect { scheduleAutoCopy(trimmed) }
    }

    /// ⌘↩ must win over a copy-on-select still waiting out its debounce.
    public func cancelAutoCopy() {
        autoCopyTask?.cancel()
    }

    /// Copy-on-select waits for the pointer to settle, so a drag copies once at
    /// its end and a double/triple click copies the word or paragraph it lands on.
    private func scheduleAutoCopy(_ text: String) {
        autoCopyTask?.cancel()
        autoCopyTask = Task { [weak self] in
            while NSEvent.pressedMouseButtons & 1 == 1 {
                try? await Task.sleep(for: .milliseconds(40))
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.writeToPasteboard(text)
            self.flashToast("Copied selection")
        }
    }

    /// MarkdownUI re-parses the whole document on every update, so deltas are
    /// coalesced to ~10 renders/second.
    public func append(_ chunk: String) {
        if isReasoning { isReasoning = false }
        accumulated += chunk
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self else { return }
            self.flushScheduled = false
            self.markdown = self.accumulated
        }
    }

    public func finish() {
        markdown = accumulated
        state = .done
    }

    public func fail(_ message: String) {
        markdown = accumulated
        state = .failed(message)
    }

    /// Falls back to the full response, not the captured selection: ⌘↩ must
    /// never silently echo the user's own input back at them.
    public var smartCopyText: String {
        SmartCopy.extract(from: fullText) ?? fullText
    }

    public var fullText: String {
        accumulated.isEmpty ? markdown : accumulated
    }
}
