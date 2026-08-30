import XCTest
@testable import HolsterKit

@MainActor
final class APIKeyStoreTests: XCTestCase {
    private final class TestAPIKeyStore: APIKeyStoring {
        var values: [String: String] = [:]

        func apiKey(for account: String) throws -> String? {
            values[account]
        }

        func setAPIKey(_ apiKey: String?, for account: String) throws {
            values[account] = apiKey
        }
    }

    func testPackagedApplicationDefaultsToKeychain() {
        XCTAssertEqual(APIKeyPersistence.defaultForApplication(at: "/Applications/Holster.app"), .keychain)
        XCTAssertEqual(APIKeyPersistence.defaultForApplication(at: "/tmp/Holster"), .configFile)
    }

    func testKeychainStoreRoundTripsAndDeletesAPIKey() throws {
        // Headless CI has no unlocked login keychain.
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil)
        let store = KeychainAPIKeyStore(service: "app.holster.tests.\(UUID().uuidString)")
        let account = "provider:test"

        try store.setAPIKey("sk-integration", for: account)
        XCTAssertEqual(try store.apiKey(for: account), "sk-integration")

        try store.setAPIKey(nil, for: account)
        XCTAssertNil(try store.apiKey(for: account))
    }

    func testProductionSaveKeepsAPIKeyOutOfConfigFile() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var draft = ConfigStore.CommandDraft()
        draft.name = "Router"
        draft.model = "m"
        draft.provider = ProviderPreset.custom
        draft.baseURL = "https://openrouter.ai/api/v1"
        draft.apiKey = "sk-production"
        draft.promptText = "{selection}"

        try fixture.store.saveCommand(originalName: nil, draft: draft)

        let yaml = try String(contentsOf: fixture.store.configFile, encoding: .utf8)
        XCTAssertFalse(yaml.contains("sk-production"))
        XCTAssertEqual(fixture.apiKeys.values["provider:custom"], "sk-production")
        XCTAssertEqual(
            fixture.store.config?.providers[ProviderPreset.custom]?.apiKey,
            "sk-production")
    }

    func testProductionLoadMigratesPlaintextAPIKeyToKeychain() throws {
        let fixture = try makeFixture(apiKey: "sk-legacy")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        fixture.store.load()

        XCTAssertNil(fixture.store.lastError)
        XCTAssertEqual(fixture.apiKeys.values["provider:local"], "sk-legacy")
        XCTAssertEqual(fixture.store.config?.providers["local"]?.apiKey, "sk-legacy")
        XCTAssertFalse(
            try String(contentsOf: fixture.store.configFile, encoding: .utf8)
                .contains("sk-legacy"))
    }

    func testProductionLoadKeepsKeychainValueWhenYAMLKeyIsEmpty() throws {
        let fixture = try makeFixture(apiKey: "", load: false)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.apiKeys.values["provider:local"] = "sk-keychain"
        let yamlBefore = try String(contentsOf: fixture.store.configFile, encoding: .utf8)

        fixture.store.load()

        XCTAssertEqual(fixture.store.config?.providers["local"]?.apiKey, "sk-keychain")
        XCTAssertEqual(fixture.apiKeys.values["provider:local"], "sk-keychain")
        // An empty api_key holds no secret, so the file must not be rewritten.
        XCTAssertEqual(
            try String(contentsOf: fixture.store.configFile, encoding: .utf8), yamlBefore)
    }

    func testProductionLoadPreservesYAMLCommentsWhenNoSecretNeedsMigration() throws {
        let fixture = try makeFixture(load: false)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try """
        # keep this comment
        providers:
          local:
            base_url: http://127.0.0.1:9999/v1
            api_key: ""  # empty on purpose
        default_provider: local
        commands:
          - name: Existing
            prompt: existing.md
            model: model-a
        """.write(
            to: fixture.store.configFile, atomically: true, encoding: .utf8)

        fixture.store.load()

        XCTAssertNil(fixture.store.lastError)
        let yaml = try String(contentsOf: fixture.store.configFile, encoding: .utf8)
        XCTAssertTrue(yaml.contains("# keep this comment"))
    }

    func testPackagedSaveWithBlankPresetAPIKeyPreservesExistingKeyAndKeepsYAMLSecretFree() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.apiKeys.values["provider:\(ProviderPreset.openCodeGo)"] = "sk-existing"

        var draft = ConfigStore.CommandDraft()
        draft.name = "Grammar Teacher"
        draft.model = "model-a"
        draft.provider = ProviderPreset.openCodeGo
        draft.promptText = "{selection}"

        try fixture.store.saveCommand(originalName: nil, draft: draft)

        XCTAssertEqual(
            fixture.apiKeys.values["provider:\(ProviderPreset.openCodeGo)"], "sk-existing")
        let yaml = try String(contentsOf: fixture.store.configFile, encoding: .utf8)
        XCTAssertFalse(yaml.contains("sk-existing"))
        XCTAssertFalse(yaml.contains("api_key"))
        XCTAssertEqual(
            fixture.store.config?.providers[ProviderPreset.openCodeGo]?.baseURL,
            ProviderPreset.openCodeGoBaseURL)
    }

    func testPackagedSaveWithBlankCustomAPIKeyPreservesExistingKeyAndKeepsYAMLSecretFree() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.apiKeys.values["provider:\(ProviderPreset.custom)"] = "sk-existing"

        var draft = ConfigStore.CommandDraft()
        draft.name = "Router"
        draft.model = "model-a"
        draft.provider = ProviderPreset.custom
        draft.baseURL = "https://openrouter.ai/api/v1"
        draft.promptText = "{selection}"

        try fixture.store.saveCommand(originalName: nil, draft: draft)

        XCTAssertEqual(
            fixture.apiKeys.values["provider:\(ProviderPreset.custom)"], "sk-existing")
        let yaml = try String(contentsOf: fixture.store.configFile, encoding: .utf8)
        XCTAssertFalse(yaml.contains("sk-existing"))
        XCTAssertFalse(yaml.contains("api_key"))
        XCTAssertEqual(
            fixture.store.config?.providers[ProviderPreset.custom]?.baseURL,
            "https://openrouter.ai/api/v1")
    }

    func testRemoveAPIKeyDeletesKeychainValueButPreservesProviderConfiguration() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.apiKeys.values["provider:local"] = "sk-remove"
        let originalProvider = try XCTUnwrap(fixture.store.config?.providers["local"])

        try fixture.store.removeAPIKey(for: "local")

        XCTAssertNil(fixture.apiKeys.values["provider:local"])
        let provider = try XCTUnwrap(fixture.store.config?.providers["local"])
        XCTAssertEqual(provider.baseURL, originalProvider.baseURL)
        XCTAssertEqual(provider.apiKey, originalProvider.apiKey)
        XCTAssertNotNil(fixture.store.command(named: "Existing"))
    }

    func testRemoveAPIKeyKeepsOtherProviderSecretsOutOfYAML() throws {
        let fixture = try makeFixture(load: false)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.apiKeys.values["provider:local"] = "sk-local"
        fixture.apiKeys.values["provider:backup"] = "sk-backup"
        try """
        providers:
          local:
            base_url: http://127.0.0.1:9999/v1
          backup:
            base_url: http://127.0.0.1:9998/v1
        default_provider: local
        commands:
          - name: Existing
            prompt: existing.md
            model: model-a
        """.write(
            to: fixture.store.configFile,
            atomically: true,
            encoding: .utf8)
        fixture.store.load()

        try fixture.store.removeAPIKey(for: "local")

        let yaml = try String(contentsOf: fixture.store.configFile, encoding: .utf8)
        XCTAssertFalse(yaml.contains("sk-local"))
        XCTAssertFalse(yaml.contains("sk-backup"))
        XCTAssertEqual(fixture.apiKeys.values["provider:backup"], "sk-backup")
    }

    func testDraftDoesNotExposeHydratedAPIKey() throws {
        let fixture = try makeFixture(load: false)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.apiKeys.values["provider:local"] = "sk-hydrated"
        fixture.store.load()

        let command = try XCTUnwrap(fixture.store.command(named: "Existing"))
        XCTAssertEqual(fixture.store.config?.providers["local"]?.apiKey, "sk-hydrated")
        XCTAssertEqual(fixture.store.draft(for: command).apiKey, "")
    }

    func testKeychainServiceIsNamespacedByConfigDirectory() throws {
        let defaultDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/holster", isDirectory: true)
        XCTAssertEqual(ConfigStore.keychainService(for: defaultDir), "app.holster.api-keys")

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("holster-ns-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let service = ConfigStore.keychainService(for: temp)
        XCTAssertTrue(service.hasPrefix("app.holster.api-keys."))
        XCTAssertNotEqual(service, ConfigStore.keychainService(for: defaultDir))

        // Symlinks and trailing slashes must not fork the namespace.
        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("holster-ns-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: temp)
        defer { try? FileManager.default.removeItem(at: link) }
        XCTAssertEqual(ConfigStore.keychainService(for: link), service)
        XCTAssertEqual(
            ConfigStore.keychainService(for: URL(fileURLWithPath: temp.path + "/")),
            service)
    }

    func testRemoveAPIKeyKeepsKeyWhenDeleteFails() throws {
        struct StubError: Error {}
        final class FailingDeleteStore: APIKeyStoring {
            var values: [String: String] = [:]
            func apiKey(for account: String) throws -> String? { values[account] }
            func setAPIKey(_ apiKey: String?, for account: String) throws {
                if apiKey == nil, values[account] != nil { throw StubError() }
                values[account] = apiKey
            }
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("holster-keychain-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("prompts"),
            withIntermediateDirectories: true)
        try """
        providers:
          local:
            base_url: http://127.0.0.1:9999/v1
        default_provider: local
        commands:
          - name: Existing
            prompt: existing.md
            model: model-a
        """.write(
            to: directory.appendingPathComponent("config.yaml"),
            atomically: true, encoding: .utf8)
        let apiKeys = FailingDeleteStore()
        apiKeys.values["provider:local"] = "sk-survives"
        let store = ConfigStore(
            directory: directory, apiKeyPersistence: .keychain, apiKeyStore: apiKeys)
        store.load()

        XCTAssertThrowsError(try store.removeAPIKey(for: "local"))

        // The failed delete must not lose the key: it is still in the store
        // and gets re-hydrated on the reload.
        XCTAssertEqual(apiKeys.values["provider:local"], "sk-survives")
        XCTAssertEqual(store.config?.providers["local"]?.apiKey, "sk-survives")
    }

    private func makeFixture(apiKey: String? = nil, load: Bool = true) throws -> (
        directory: URL, store: ConfigStore, apiKeys: TestAPIKeyStore
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("holster-keychain-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("prompts"),
            withIntermediateDirectories: true)
        let apiKeyLine = apiKey.map { "    api_key: \"\($0)\"\n" } ?? ""
        try """
        providers:
          local:
            base_url: http://127.0.0.1:9999/v1
        \(apiKeyLine)default_provider: local
        commands:
          - name: Existing
            prompt: existing.md
            model: model-a
        """.write(
            to: directory.appendingPathComponent("config.yaml"),
            atomically: true,
            encoding: .utf8)
        try "{selection}".write(
            to: directory.appendingPathComponent("prompts/existing.md"),
            atomically: true,
            encoding: .utf8)
        let apiKeys = TestAPIKeyStore()
        let store = ConfigStore(
            directory: directory,
            apiKeyPersistence: .keychain,
            apiKeyStore: apiKeys)
        if load {
            store.load()
        }
        return (directory, store, apiKeys)
    }
}
