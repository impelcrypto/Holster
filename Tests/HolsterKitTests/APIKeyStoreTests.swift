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

        fixture.store.load()

        XCTAssertEqual(fixture.store.config?.providers["local"]?.apiKey, "sk-keychain")
        XCTAssertEqual(fixture.apiKeys.values["provider:local"], "sk-keychain")
        XCTAssertFalse(
            try String(contentsOf: fixture.store.configFile, encoding: .utf8)
                .contains("api_key"))
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
