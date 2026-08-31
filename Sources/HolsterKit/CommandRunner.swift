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
    private weak var currentViewModel: RunViewModel?

    public init(store: ConfigStore, speaker: Speaker) {
        self.store = store
        self.speaker = speaker
    }

    public func run(_ command: CommandConfig) {
        start(command, selection: nil)
    }

    private func start(_ command: CommandConfig, selection: String?) {
        currentTask?.cancel()
        // A superseded run's selector would otherwise land later, overwrite the
        // clipboard, and close the panel this run is about to present.
        currentViewModel?.cancelSmartCopy()
        speaker.stop()

        let viewModel = RunViewModel(command: command)
        currentViewModel = viewModel
        viewModel.onCopied = { [weak self] in self?.panel.close() }
        viewModel.onSpeak = { [weak self] text in
            self?.speaker.speak(text, config: self?.store.config?.tts)
        }
        viewModel.onRetry = { [weak self, weak viewModel] in
            guard let self else { return }
            self.start(command, selection: viewModel?.selection)
        }
        viewModel.onStop = { [weak self, weak viewModel] in
            self?.currentTask?.cancel()
            viewModel?.finish()
        }
        viewModel.onSmartCopy = { [weak self, weak viewModel] response in
            guard let self, let viewModel else { return nil }
            return await self.selectCopyTarget(command, response: response, viewModel: viewModel)
        }
        panel.onClose = { [weak self, weak viewModel] in
            self?.currentTask?.cancel()
            viewModel?.cancelSmartCopy()
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
            let clipboard = NSPasteboard.general.string(forType: .string)
            let prompt = PromptTemplate.render(template, selection: selection, clipboard: clipboard)
            viewModel.renderedPrompt = prompt
            let requests = try config.makeRequests(for: command, prompt: prompt)
            let fallback = config.resolveFallback(for: command)

            for try await event in LLMClient.streamWithFallback(
                requests.primary, fallback: requests.fallback) {
                guard !Task.isCancelled else { return }
                switch event {
                case .reasoning: viewModel.noteReasoning()
                case .content(let chunk): viewModel.append(chunk)
                case .fallback:
                    if let fallback {
                        viewModel.noteFallback(providerName: fallback.name, model: fallback.model)
                    }
                }
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

    /// One extra non-streaming request on the command's own provider. Ten
    /// seconds per attempt: ⌘↩ is a clipboard action, not a generation.
    private func selectCopyTarget(
        _ command: CommandConfig,
        response: String,
        viewModel: RunViewModel
    ) async -> String? {
        let context = SmartCopySelector.Context(
            commandName: command.name,
            // The rendered prompt, not a re-read of the file: it carries the
            // clipboard only when the template actually asked for it.
            instructions: viewModel.renderedPrompt ?? "",
            selection: viewModel.selection ?? "")
        guard let config = store.config,
              let requests = try? config.makeRequests(
                  for: command,
                  prompt: SmartCopySelector.makePrompt(context: context, response: response),
                  system: SmartCopySelector.systemPrompt,
                  stream: false,
                  timeout: 10)
        else { return nil }
        return await SmartCopySelector.run(
            response: response, primary: requests.primary, fallback: requests.fallback)
    }

    private func makeView(_ viewModel: RunViewModel) -> ResultView {
        ResultView(model: viewModel) { [weak self] height in
            self?.panel.adjustContentHeight(height)
        }
    }
}
