import AppKit
import Foundation

/// Process entry point. `--run` and friends execute headless (no GUI, no
/// permissions); anything else boots the menu bar app.
@MainActor
public func mainEntry() async {
    let args = Array(CommandLine.arguments.dropFirst())
    if let code = await CLIMode.runIfRequested(args: args) {
        exit(code)
    }
    HolsterApp.main()
}

enum CLIMode {
    private static let usage = """
    Holster — prompt templates on selected text, from your menu bar

    Headless usage (no permissions needed):
      Holster --run <command-name> --text <text>   Run a command on <text>
      Holster --run <command-name>                 ... reading text from stdin
      Holster --list                               List configured commands
      Holster --help                               Show this help

    Options:
      --config <dir>   Config directory (default ~/.config/holster)
      --no-stream      Wait for the full response instead of streaming

    Launching with no arguments starts the menu bar app.
    """

    /// Returns an exit code when args request CLI mode, nil otherwise.
    @MainActor
    static func runIfRequested(args: [String]) async -> Int32? {
        guard !args.isEmpty else { return nil }
        var runName: String?
        var text: String?
        var configDir: URL?
        var noStream = false
        var list = false

        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--help", "-h":
                print(usage)
                return 0
            case "--list":
                list = true
            case "--no-stream":
                noStream = true
            case "--run":
                runName = iterator.next()
            case "--text":
                text = iterator.next()
            case "--config":
                if let dir = iterator.next() {
                    configDir = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
                }
            default:
                return fail("Unknown argument: \(arg)\n\n\(usage)")
            }
        }

        let store = ConfigStore(directory: configDir)
        store.loadOnce()
        if let error = store.lastError {
            return fail(error)
        }
        guard let config = store.config else {
            return fail("No config loaded from \(store.configFile.path)")
        }

        if list {
            for command in config.commands {
                let hotkey = command.hotkey.map { "  [\($0)]" } ?? ""
                print("\(command.name)  (\(command.model))\(hotkey)")
            }
            return 0
        }

        guard let runName else {
            return fail("Nothing to do. Try --help.")
        }
        guard let command = store.command(named: runName) else {
            let names = config.commands.map(\.name).joined(separator: ", ")
            return fail("Unknown command \"\(runName)\". Available: \(names)")
        }

        let input: String
        if let text {
            input = text
        } else {
            guard let data = try? FileHandle.standardInput.readToEnd(),
                  let stdinText = String(data: data, encoding: .utf8),
                  !stdinText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return fail("No input: pass --text or pipe text on stdin")
            }
            input = stdinText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        do {
            let template = try store.promptText(for: command)
            let provider = try config.resolveProvider(for: command).provider
            let clipboard = NSPasteboard.general.string(forType: .string)
            let request = LLMRequest(
                baseURL: provider.baseURL,
                apiKey: provider.apiKey,
                model: command.model,
                prompt: PromptTemplate.render(template, selection: input, clipboard: clipboard),
                temperature: command.temperature,
                stream: noStream ? false : command.wantsStream)
            for try await chunk in LLMClient.stream(request) {
                fputs(chunk, stdout)
                fflush(stdout)
            }
            fputs("\n", stdout)
            return 0
        } catch {
            return fail(error.localizedDescription)
        }
    }

    private static func fail(_ message: String) -> Int32 {
        fputs("Holster: \(message)\n", stderr)
        return 1
    }
}
