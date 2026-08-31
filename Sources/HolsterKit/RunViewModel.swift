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
    /// The Smart Copy selector request is in flight.
    @Published public private(set) var isSelecting = false

    public let commandName: String
    /// Switches to the fallback model name when the primary provider fails.
    @Published public private(set) var modelName: String

    /// The captured selection; retry reuses it.
    public var selection: String?
    /// The prompt actually sent, so Smart Copy sees the task the model saw.
    public var renderedPrompt: String?

    public var onRetry: (() -> Void)?
    public var onSpeak: ((String) -> Void)?
    public var onCopied: (() -> Void)?
    public var onStop: (() -> Void)?
    /// Picks the part of the response worth pasting; nil means copy it whole.
    public var onSmartCopy: ((String) async -> String?)?

    private let copyOnSelect: Bool
    private var accumulated = ""
    private var flushScheduled = false
    private var toastTask: Task<Void, Never>?
    private var autoCopyTask: Task<Void, Never>?
    private var smartCopyTask: Task<Void, Never>?

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
                // A cancelled sleep returns at once, so without this the loop
                // spins on the MainActor until the mouse button comes up.
                if Task.isCancelled { return }
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

    /// ⌘↩: ask the selector what to paste, then copy and close. A failed or
    /// cancelled selection falls back to the full response, never to the
    /// captured selection — ⌘↩ must not echo the user's own input back.
    public func performSmartCopy() {
        guard state == .done, smartCopyTask == nil else { return }
        cancelAutoCopy()
        let response = fullText
        isSelecting = true
        smartCopyTask = Task { [weak self] in
            let picked = await self?.onSmartCopy?(response)
            guard !Task.isCancelled, let self else { return }
            self.isSelecting = false
            self.smartCopyTask = nil
            self.writeToPasteboard(picked ?? response)
            self.onCopied?()
        }
    }

    /// ⇧⌘↩: the whole response, right now, window stays open.
    public func copyAll() {
        // Without this an in-flight selector would land moments later and
        // overwrite what the user just deliberately took.
        cancelSmartCopy()
        cancelAutoCopy()
        writeToPasteboard(fullText)
        flashToast("Copied")
    }

    /// Esc or a closing panel: no clipboard write may follow.
    public func cancelSmartCopy() {
        smartCopyTask?.cancel()
        smartCopyTask = nil
        isSelecting = false
    }

    public var fullText: String {
        accumulated.isEmpty ? markdown : accumulated
    }
}
