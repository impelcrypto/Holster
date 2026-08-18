import Combine
import Foundation

@MainActor
public final class ConfigStore: ObservableObject {
    @Published public private(set) var config: Config?
    @Published public private(set) var lastError: String?

    public let directory: URL
    public var configFile: URL { directory.appendingPathComponent("config.yaml") }
    public var promptsDirectory: URL { directory.appendingPathComponent("prompts") }

    /// Called after every successful (re)load, e.g. to re-register hotkeys.
    public var onReload: ((Config) -> Void)?

    private var watchers: [DirectoryWatcher] = []
    private var reloadWorkItem: DispatchWorkItem?

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/holster", isDirectory: true)
    }

    /// Full app startup: seed examples on first run, load, then watch files.
    public func bootstrapAndLoad() {
        installExamplesIfNeeded()
        load()
        startWatching()
    }

    /// CLI startup: no watching.
    public func loadOnce() {
        installExamplesIfNeeded()
        load()
    }

    public func load() {
        do {
            let yaml = try String(contentsOf: configFile, encoding: .utf8)
            let parsed = try Config.parse(yaml: yaml)
            config = parsed
            lastError = nil
            onReload?(parsed)
        } catch let error as ConfigError {
            lastError = error.localizedDescription
        } catch {
            lastError = "Cannot read \(configFile.path): \(error.localizedDescription)"
        }
    }

    public func command(named name: String) -> CommandConfig? {
        config?.commands.first { $0.name == name }
    }

    public func promptText(for command: CommandConfig) throws -> String {
        let url = promptsDirectory.appendingPathComponent(command.prompt)
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigError.unreadable("prompt file \(url.path)")
        }
    }

    // MARK: - First run

    private func installExamplesIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: configFile.path) else { return }
        guard let examples = Bundle.module.url(forResource: "examples", withExtension: nil) else { return }
        do {
            try fm.createDirectory(at: promptsDirectory, withIntermediateDirectories: true)
            try fm.copyItem(
                at: examples.appendingPathComponent("config.yaml"),
                to: configFile)
            let examplePrompts = examples.appendingPathComponent("prompts")
            for file in try fm.contentsOfDirectory(at: examplePrompts, includingPropertiesForKeys: nil) {
                let target = promptsDirectory.appendingPathComponent(file.lastPathComponent)
                if !fm.fileExists(atPath: target.path) {
                    try fm.copyItem(at: file, to: target)
                }
            }
        } catch {
            lastError = "First-run setup failed: \(error.localizedDescription)"
        }
    }

    // MARK: - File watching

    private func startWatching() {
        watchers = [directory, promptsDirectory].compactMap { url in
            DirectoryWatcher(url: url) { [weak self] in
                Task { @MainActor in self?.scheduleReload() }
            }
        }
    }

    /// Editors save via rename and often touch the dir several times; debounce.
    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.load() }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}

final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject
    private let descriptor: Int32

    init?(url: URL, onChange: @escaping @Sendable () -> Void) {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .global(qos: .utility))
        source.setEventHandler(handler: onChange)
        let fd = descriptor
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
