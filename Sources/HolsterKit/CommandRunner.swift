import AppKit
import Foundation

/// Orchestrates one command run: capture selection → render prompt → stream
/// into the floating panel.
@MainActor
public final class CommandRunner {
    private let store: ConfigStore
    private let speaker: Speaker
    private lazy var panel = ResultPanel()
    private var currentTask: Task<Void, Never>?

    public init(store: ConfigStore, speaker: Speaker) {
        self.store = store
        self.speaker = speaker
    }

    public func run(_ command: CommandConfig) {
        start(command, selection: nil)
    }

    private func start(_ command: CommandConfig, selection: String?) {
        currentTask?.cancel()
        speaker.stop()

        let viewModel = RunViewModel(command: command)
        viewModel.onCopied = { [weak self] in self?.panel.close() }
        viewModel.onSpeak = { [weak self] text in
            self?.speaker.speak(text, config: self?.store.config?.tts)
        }
        viewModel.onRetry = { [weak self, weak viewModel] in
            guard let self else { return }
            self.start(command, selection: viewModel?.selection)
        }
        panel.autoCopyOnSelect = command.wantsCopyOnSelect
        panel.onAutoCopy = { [weak viewModel] in
            viewModel?.flashToast("Copied selection")
        }

        currentTask = Task { [weak self] in
            await self?.execute(command, presetSelection: selection, viewModel: viewModel)
        }
    }

    private func execute(
        _ command: CommandConfig,
        presetSelection: String?,
        viewModel: RunViewModel
    ) async {
        // The panel may only appear AFTER the selection is captured: once it
        // becomes the key window it owns global keyboard focus, and the
        // synthetic ⌘C would land in our own panel instead of the user's app.
        var presented = false
        do {
            let selection: String
            if let presetSelection {
                selection = presetSelection
            } else {
                // Re-trigger while our panel holds key focus (⌘E again, Retry):
                // hide it so orderOut hands key back to the user's app first.
                if panel.isKeyWindow {
                    panel.orderOut(nil)
                    try? await Task.sleep(for: .milliseconds(150))
                }
                selection = try await SelectionCapture.capture()
            }
            guard !Task.isCancelled else { return }
            viewModel.selection = selection
            viewModel.beginStreaming()
            panel.present(makeView(viewModel))
            presented = true

            let template = try store.promptText(for: command)
            guard let config = store.config else {
                throw ConfigError.validation("No valid config loaded")
            }
            let provider = try config.resolveProvider(for: command).provider
            let clipboard = NSPasteboard.general.string(forType: .string)
            let request = LLMRequest(
                baseURL: provider.baseURL,
                apiKey: provider.apiKey,
                model: command.model,
                prompt: PromptTemplate.render(template, selection: selection, clipboard: clipboard),
                temperature: command.temperature,
                stream: command.wantsStream)

            for try await chunk in LLMClient.stream(request) {
                guard !Task.isCancelled else { return }
                viewModel.append(chunk)
            }
            viewModel.finish()
        } catch is CancellationError {
            // Superseded by a newer run.
        } catch {
            guard !Task.isCancelled else { return }
            viewModel.fail(error.localizedDescription)
            if !presented {
                panel.present(makeView(viewModel))
            }
        }
    }

    private func makeView(_ viewModel: RunViewModel) -> ResultView {
        ResultView(model: viewModel) { [weak self] height in
            self?.panel.adjustContentHeight(height)
        }
    }
}
