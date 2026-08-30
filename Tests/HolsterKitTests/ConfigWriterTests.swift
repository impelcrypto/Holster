import XCTest
@testable import HolsterKit

@MainActor
final class ConfigWriterTests: XCTestCase {
    private var directory: URL!
    private var store: ConfigStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("holster-tests-\(UUID().uuidString)")
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
        try "Old prompt {selection}".write(
            to: directory.appendingPathComponent("prompts/existing.md"),
            atomically: true, encoding: .utf8)
        store = ConfigStore(directory: directory)
        store.load()
        XCTAssertNil(store.lastError)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveNewCommandRoundTrips() throws {
        var draft = ConfigStore.CommandDraft()
        draft.name = "Grammar Teacher"
        draft.hotkey = "cmd+shift+g"
        draft.provider = "local"
        draft.model = "model-b"
        draft.reasoning = "high"
        draft.promptText = "Check: {selection}"
        try store.saveCommand(originalName: nil, draft: draft)

        let saved = try XCTUnwrap(store.command(named: "Grammar Teacher"))
        XCTAssertEqual(saved.model, "model-b")
        XCTAssertEqual(saved.hotkey, "cmd+shift+g")
        XCTAssertEqual(saved.reasoning, "high")
        XCTAssertEqual(saved.prompt, "grammar-teacher.md")
        XCTAssertEqual(try store.promptText(for: saved), "Check: {selection}")
        // The rewritten YAML must survive a fresh parse.
        let reparsed = try Config.parse(yaml: String(
            contentsOf: directory.appendingPathComponent("config.yaml"), encoding: .utf8))
        XCTAssertEqual(reparsed.commands.count, 2)
    }

    func testEditKeepsPromptFileName() throws {
        let existing = try XCTUnwrap(store.command(named: "Existing"))
        var draft = store.draft(for: existing)
        draft.model = "model-z"
        draft.promptText = "New text {selection}"
        try store.saveCommand(originalName: "Existing", draft: draft)

        let saved = try XCTUnwrap(store.command(named: "Existing"))
        XCTAssertEqual(saved.model, "model-z")
        XCTAssertEqual(saved.prompt, "existing.md")
        XCTAssertEqual(try store.promptText(for: saved), "New text {selection}")
    }

    func testSaveTTSRoundTrips() throws {
        try store.saveTTS(voice: "en-US-EmmaNeural")
        XCTAssertEqual(store.config?.tts?.provider, "edge")
        XCTAssertEqual(store.config?.tts?.voice, "en-US-EmmaNeural")
        // The rewritten YAML must survive a fresh parse.
        let reparsed = try Config.parse(yaml: String(
            contentsOf: directory.appendingPathComponent("config.yaml"), encoding: .utf8))
        XCTAssertEqual(reparsed.tts?.voice, "en-US-EmmaNeural")
        XCTAssertEqual(reparsed.commands.count, 1)
    }

    func testSaveTTSPreservesConfiguredEndpoint() throws {
        try """
        providers:
          local:
            base_url: http://127.0.0.1:9999/v1
        default_provider: local
        tts:
          base_url: https://api.openai.com/v1
          model: gpt-4o-mini-tts
          voice: alloy
        commands:
          - name: Existing
            prompt: existing.md
            model: model-a
        """.write(
            to: directory.appendingPathComponent("config.yaml"),
            atomically: true, encoding: .utf8)
        store.load()
        XCTAssertNil(store.lastError)

        try store.saveTTS(voice: "en-US-EmmaNeural")

        // Picking a voice must not clobber an OpenAI-compatible TTS setup.
        XCTAssertEqual(store.config?.tts?.baseURL, "https://api.openai.com/v1")
        XCTAssertNil(store.config?.tts?.provider)
        XCTAssertEqual(store.config?.tts?.model, "gpt-4o-mini-tts")
        XCTAssertEqual(store.config?.tts?.voice, "en-US-EmmaNeural")
    }

    func testDeleteRemovesCommandButKeepsPromptFile() throws {
        try store.deleteCommand(named: "Existing")
        XCTAssertNil(store.command(named: "Existing"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("prompts/existing.md").path))
    }

    func testRejectsInvalidReasoning() {
        var draft = ConfigStore.CommandDraft()
        draft.name = "X"
        draft.model = "m"
        draft.reasoning = "extreme"
        XCTAssertThrowsError(try store.saveCommand(originalName: nil, draft: draft))
    }

    func testRejectsEmptyName() {
        var draft = ConfigStore.CommandDraft()
        draft.name = "   "
        draft.model = "m"
        XCTAssertThrowsError(try store.saveCommand(originalName: nil, draft: draft))
    }

    func testCopyOnSelectRoundTrips() throws {
        var draft = ConfigStore.CommandDraft()
        draft.name = "AutoCopy"
        draft.model = "m"
        draft.provider = "local"
        draft.copyOnSelect = true
        draft.promptText = "{selection}"
        try store.saveCommand(originalName: nil, draft: draft)
        let saved = try XCTUnwrap(store.command(named: "AutoCopy"))
        XCTAssertTrue(saved.wantsCopyOnSelect)
        // Default stays off and is omitted from YAML.
        let existing = try XCTUnwrap(store.command(named: "Existing"))
        XCTAssertFalse(existing.wantsCopyOnSelect)
    }

    func testCustomProviderIsUpsertedOnSave() throws {
        var draft = ConfigStore.CommandDraft()
        draft.name = "Router"
        draft.model = "m"
        draft.provider = ProviderPreset.custom
        draft.baseURL = "https://openrouter.ai/api/v1"
        draft.apiKey = "sk-test"
        draft.promptText = "{selection}"
        try store.saveCommand(originalName: nil, draft: draft)

        let provider = try XCTUnwrap(store.config?.providers[ProviderPreset.custom])
        XCTAssertEqual(provider.baseURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(provider.apiKey, "sk-test")
        XCTAssertEqual(store.command(named: "Router")?.provider, ProviderPreset.custom)
    }

    func testCustomProviderRequiresBaseURL() {
        var draft = ConfigStore.CommandDraft()
        draft.name = "Router"
        draft.model = "m"
        draft.provider = ProviderPreset.custom
        XCTAssertThrowsError(try store.saveCommand(originalName: nil, draft: draft))
    }

    func testFallbackRoundTrips() throws {
        var draft = ConfigStore.CommandDraft()
        draft.name = "WithFallback"
        draft.model = "m"
        draft.provider = "local"
        draft.fallbackProvider = "local"
        draft.fallbackModel = "m-backup"
        draft.promptText = "{selection}"
        try store.saveCommand(originalName: nil, draft: draft)

        let saved = try XCTUnwrap(store.command(named: "WithFallback"))
        XCTAssertEqual(saved.fallbackProvider, "local")
        XCTAssertEqual(saved.fallbackModel, "m-backup")
        XCTAssertEqual(store.draft(for: saved).fallbackProvider, "local")
        XCTAssertEqual(store.draft(for: saved).fallbackModel, "m-backup")
    }

    func testFallbackModelIsDroppedWithoutFallbackProvider() throws {
        var draft = ConfigStore.CommandDraft()
        draft.name = "NoFallback"
        draft.model = "m"
        draft.provider = "local"
        draft.fallbackModel = "orphan"
        draft.promptText = "{selection}"
        try store.saveCommand(originalName: nil, draft: draft)

        let saved = try XCTUnwrap(store.command(named: "NoFallback"))
        XCTAssertNil(saved.fallbackProvider)
        XCTAssertNil(saved.fallbackModel)
        let yaml = try String(
            contentsOf: directory.appendingPathComponent("config.yaml"), encoding: .utf8)
        XCTAssertFalse(yaml.contains("fallback_model"))
    }

    func testRejectsUnknownFallbackProvider() {
        var draft = ConfigStore.CommandDraft()
        draft.name = "X"
        draft.model = "m"
        draft.provider = "local"
        draft.fallbackProvider = "missing"
        XCTAssertThrowsError(try store.saveCommand(originalName: nil, draft: draft))
    }

    func testOpenCodeGoPresetGetsCanonicalBaseURL() throws {
        var draft = ConfigStore.CommandDraft()
        draft.name = "Go"
        draft.model = "m"
        draft.provider = ProviderPreset.openCodeGo
        draft.apiKey = "sk-go"
        draft.promptText = "{selection}"
        try store.saveCommand(originalName: nil, draft: draft)

        let provider = try XCTUnwrap(store.config?.providers[ProviderPreset.openCodeGo])
        XCTAssertEqual(provider.baseURL, ProviderPreset.openCodeGoBaseURL)
        XCTAssertEqual(provider.apiKey, "sk-go")
    }

    func testPromptTextRejectsTraversal() throws {
        try "secret".write(
            to: directory.appendingPathComponent("secret.md"),
            atomically: true, encoding: .utf8)
        let command = CommandConfig(name: "Evil", prompt: "../secret.md", model: "m")
        XCTAssertThrowsError(try store.promptText(for: command)) { error in
            guard case ConfigError.validation = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
        }
    }

    func testPromptTextRejectsSymlinkEscape() throws {
        let outside = directory.appendingPathComponent("outside.md")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        let link = directory.appendingPathComponent("prompts/link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let command = CommandConfig(name: "Evil", prompt: "link.md", model: "m")
        XCTAssertThrowsError(try store.promptText(for: command))
    }

    func testSaveRejectsPromptFileOutsidePromptsDirectory() throws {
        let existing = try XCTUnwrap(store.command(named: "Existing"))
        var draft = store.draft(for: existing)
        draft.promptFile = "../escape.md"
        draft.promptText = "evil"
        XCTAssertThrowsError(try store.saveCommand(originalName: "Existing", draft: draft))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("escape.md").path))
    }

    func testSaveAppliesRestrictivePermissions() throws {
        var draft = ConfigStore.CommandDraft()
        draft.name = "Perms"
        draft.model = "m"
        draft.provider = "local"
        draft.promptText = "{selection}"
        try store.saveCommand(originalName: nil, draft: draft)

        let fm = FileManager.default
        let configMode = try XCTUnwrap(
            fm.attributesOfItem(atPath: store.configFile.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(configMode.uint16Value, 0o600)
        let promptMode = try XCTUnwrap(
            fm.attributesOfItem(
                atPath: directory.appendingPathComponent("prompts/perms.md").path)[
                    .posixPermissions] as? NSNumber)
        XCTAssertEqual(promptMode.uint16Value, 0o600)
    }

    func testGeminiPresetGetsCanonicalBaseURL() throws {
        var draft = ConfigStore.CommandDraft()
        draft.name = "Gemini"
        draft.model = "models/gemini-3.7-flash"
        draft.provider = ProviderPreset.gemini
        draft.apiKey = "gemini-key"
        draft.promptText = "{selection}"
        try store.saveCommand(originalName: nil, draft: draft)

        let provider = try XCTUnwrap(store.config?.providers[ProviderPreset.gemini])
        XCTAssertEqual(provider.baseURL, ProviderPreset.geminiBaseURL)
        XCTAssertEqual(provider.apiKey, "gemini-key")
        let command = try XCTUnwrap(store.command(named: "Gemini"))
        XCTAssertEqual(command.provider, ProviderPreset.gemini)
        XCTAssertEqual(command.model, "gemini-3.7-flash")
        let yaml = try String(contentsOf: store.configFile, encoding: .utf8)
        XCTAssertFalse(yaml.contains("models/gemini-3.7-flash"))
    }
}
