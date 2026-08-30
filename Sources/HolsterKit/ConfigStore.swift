import Combine
import CryptoKit
import Foundation
import Security
import Yams

public protocol APIKeyStoring {
    func apiKey(for account: String) throws -> String?
    func setAPIKey(_ apiKey: String?, for account: String) throws
}

public enum APIKeyPersistence: Equatable {
    case configFile
    case keychain

    public static var applicationDefault: APIKeyPersistence {
        defaultForApplication(at: Bundle.main.bundlePath)
    }

    public static func defaultForApplication(at bundlePath: String) -> APIKeyPersistence {
        bundlePath.hasSuffix(".app") ? .keychain : .configFile
    }
}

public struct KeychainAPIKeyStore: APIKeyStoring {
    private let service: String

    public init(service: String = "app.holster.api-keys") {
        self.service = service
    }

    public func apiKey(for account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            throw APIKeyStoreError(status: status)
        }
        return apiKey
    }

    public func setAPIKey(_ apiKey: String?, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let apiKey, !apiKey.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw APIKeyStoreError(status: status)
            }
            return
        }

        let data = Data(apiKey.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError(status: updateStatus)
        }
        var attributes = query
        attributes[kSecValueData as String] = data
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError(status: addStatus)
        }
    }
}

private struct APIKeyStoreError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Cannot access API key in Keychain: \(detail)"
    }
}

@MainActor
public final class ConfigStore: ObservableObject {
    @Published public private(set) var config: Config?
    @Published public private(set) var lastError: String?
    /// True when this launch created ~/.config/holster from the bundled
    /// examples — the signal to open the first-run setup guide.
    @Published public private(set) var didSeedExamples = false

    public let directory: URL
    public var configFile: URL { directory.appendingPathComponent("config.yaml") }
    public var promptsDirectory: URL { directory.appendingPathComponent("prompts") }

    public let apiKeyPersistence: APIKeyPersistence

    /// Called after every successful (re)load, e.g. to re-register hotkeys.
    public var onReload: ((Config) -> Void)?

    private var watchers: [DirectoryWatcher] = []
    private var reloadWorkItem: DispatchWorkItem?
    private let apiKeyStore: APIKeyStoring

    public init(
        directory: URL? = nil,
        apiKeyPersistence: APIKeyPersistence = .applicationDefault,
        apiKeyStore: APIKeyStoring? = nil
    ) {
        let resolved = directory ?? Self.defaultDirectory
        self.directory = resolved
        self.apiKeyPersistence = apiKeyPersistence
        self.apiKeyStore = apiKeyStore
            ?? KeychainAPIKeyStore(service: Self.keychainService(for: resolved))
    }

    private static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/holster", isDirectory: true)
    }

    /// The default config dir keeps the legacy service so existing items keep
    /// working; alternate --config dirs get their own namespace so credentials
    /// never leak across configs.
    static func keychainService(for directory: URL) -> String {
        let canonical = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let base = "app.holster.api-keys"
        guard canonical != defaultDirectory.standardizedFileURL.resolvingSymlinksInPath().path else {
            return base
        }
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let suffix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(base).\(suffix)"
    }

    /// Full app startup: seed examples on first run, load, then watch files.
    public func bootstrapAndLoad() {
        installExamplesIfNeeded()
        normalizePermissions()
        load()
        startWatching()
    }

    /// config.yaml can hold plaintext keys (CLI mode), so keep it 0600 and the
    /// directories 0700 even when they predate this build.
    private func normalizePermissions() {
        let fm = FileManager.default
        for dir in [directory, promptsDirectory] where fm.fileExists(atPath: dir.path) {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
        if fm.fileExists(atPath: configFile.path) {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
        }
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
            let loaded = try loadAPIKeys(into: parsed)
            config = loaded
            lastError = nil
            onReload?(loaded)
        } catch let error as ConfigError {
            lastError = error.localizedDescription
        } catch let error as APIKeyStoreError {
            // A locked or denied Keychain is not a config-file problem;
            // misattributing it sends the user to the wrong fix.
            lastError = error.localizedDescription
        } catch {
            lastError = "Cannot read \(configFile.path): \(error.localizedDescription)"
        }
    }

    public func command(named name: String) -> CommandConfig? {
        config?.commands.first { $0.name == name }
    }

    public func promptText(for command: CommandConfig) throws -> String {
        let url = try resolvePromptURL(command.prompt)
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigError.unreadable("prompt file \(url.path)")
        }
    }

    /// Rejects prompt names that resolve outside prompts/ (../, symlinks): a
    /// tampered config must not read or overwrite arbitrary files.
    func resolvePromptURL(_ name: String) throws -> URL {
        let root = promptsDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = promptsDirectory.appendingPathComponent(name)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.pathComponents.count > root.pathComponents.count,
              candidate.pathComponents.starts(with: root.pathComponents) else {
            throw ConfigError.validation(
                "Prompt file \"\(name)\" must live inside \(root.path)")
        }
        return candidate
    }

    func write(_ config: Config) throws {
        let persisted = try persistAPIKeys(from: config)
        try writeConfigFile(persisted)
        load()
    }

    public func removeAPIKey(for providerName: String) throws {
        guard var updated = config, updated.providers[providerName] != nil else {
            throw ConfigError.validation("Unknown provider \"\(providerName)\"")
        }
        // Config write comes first: if it fails, the key is still in Keychain
        // instead of being irreversibly gone.
        updated.providers[providerName]?.apiKey = nil
        let persisted = try persistAPIKeys(from: updated)
        try writeConfigFile(persisted)
        defer { load() }
        if apiKeyPersistence == .keychain {
            try apiKeyStore.setAPIKey(nil, for: "provider:\(providerName)")
        }
    }

    private func loadAPIKeys(into config: Config) throws -> Config {
        guard apiKeyPersistence == .keychain else { return config }
        var hydrated = config
        var persisted = config
        var needsMigration = false

        // Only a real plaintext secret triggers the migration rewrite: an
        // empty api_key has nothing to protect, and the rewrite would destroy
        // the YAML comments of a freshly installed example config.
        for (name, provider) in config.providers {
            let account = "provider:\(name)"
            if let apiKey = provider.apiKey, !apiKey.isEmpty {
                try apiKeyStore.setAPIKey(apiKey, for: account)
                persisted.providers[name]?.apiKey = nil
                needsMigration = true
            } else {
                hydrated.providers[name]?.apiKey = try apiKeyStore.apiKey(for: account)
            }
        }
        if let apiKey = config.tts?.apiKey, !apiKey.isEmpty {
            try apiKeyStore.setAPIKey(apiKey, for: "tts")
            persisted.tts?.apiKey = nil
            needsMigration = true
        } else {
            hydrated.tts?.apiKey = try apiKeyStore.apiKey(for: "tts")
        }
        if needsMigration {
            try writeConfigFile(persisted)
        }
        return hydrated
    }

    private func persistAPIKeys(from config: Config) throws -> Config {
        guard apiKeyPersistence == .keychain else { return config }
        var persisted = config
        for (name, provider) in config.providers {
            if let apiKey = provider.apiKey {
                try apiKeyStore.setAPIKey(apiKey.isEmpty ? nil : apiKey, for: "provider:\(name)")
            }
            persisted.providers[name]?.apiKey = nil
        }
        if let apiKey = config.tts?.apiKey {
            try apiKeyStore.setAPIKey(apiKey.isEmpty ? nil : apiKey, for: "tts")
        }
        persisted.tts?.apiKey = nil
        return persisted
    }

    private func writeConfigFile(_ config: Config) throws {
        let yaml = try YAMLEncoder().encode(config)
        try yaml.write(to: configFile, atomically: true, encoding: .utf8)
        // Atomic write = temp file + rename, so the mode is set afterwards.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: configFile.path)
    }

    // MARK: - First run

    private func installExamplesIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: configFile.path) else { return }
        guard let examples = Bundle.module.url(forResource: "examples", withExtension: nil) else { return }
        do {
            try fm.createDirectory(
                at: promptsDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
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
            didSeedExamples = true
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

    init?(url: URL, onChange: @escaping @Sendable () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .global(qos: .utility))
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
