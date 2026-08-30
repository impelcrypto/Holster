import XCTest
@testable import HolsterKit

final class ConfigTests: XCTestCase {
    private let validYAML = """
    providers:
      cliproxy:
        base_url: http://127.0.0.1:8317/v1
        api_key: ""
      ollama:
        base_url: http://127.0.0.1:11434/v1
    default_provider: cliproxy
    tts:
      base_url: ""
      model: gpt-4o-mini-tts
      voice: alloy
    commands:
      - name: Grammar Teacher
        hotkey: cmd+shift+g
        prompt: grammar.md
        provider: cliproxy
        model: gpt-5.6-sol
        reasoning: medium
    """

    func testParsesValidConfig() throws {
        let config = try Config.parse(yaml: validYAML)
        XCTAssertEqual(config.providers.count, 2)
        XCTAssertEqual(config.defaultProvider, "cliproxy")
        XCTAssertEqual(config.commands.count, 1)
        let command = config.commands[0]
        XCTAssertEqual(command.name, "Grammar Teacher")
        XCTAssertEqual(command.model, "gpt-5.6-sol")
        XCTAssertEqual(command.reasoning, "medium")
        let resolved = try config.resolveProvider(for: command)
        XCTAssertEqual(resolved.name, "cliproxy")
        XCTAssertEqual(resolved.provider.baseURL, "http://127.0.0.1:8317/v1")
    }

    func testLegacyKeysAreIgnored() throws {
        let config = try Config.parse(yaml: """
        providers:
          p:
            base_url: http://localhost:1/v1
        commands:
          - name: X
            prompt: x.md
            model: m
            temperature: 0
            stream: true
        """)
        XCTAssertEqual(config.commands[0].name, "X")
    }

    func testReasoningDefaults() {
        let command = CommandConfig(name: "X", prompt: "x.md", model: "m")
        XCTAssertEqual(command.resolvedReasoning(providerName: "opencode-go", model: "m"), "low")
        XCTAssertNil(command.resolvedReasoning(providerName: "cliproxy", model: "m"))
        XCTAssertEqual(
            command.resolvedReasoning(providerName: "cliproxy", model: "gpt-5.6-terra"), "none")
        let explicit = CommandConfig(name: "X", prompt: "x.md", model: "m", reasoning: "high")
        XCTAssertEqual(
            explicit.resolvedReasoning(providerName: "cliproxy", model: "gpt-5.6-terra"), "high")
    }

    func testGeminiResourceModelNameIsNormalizedWhenConfigLoads() throws {
        let config = try Config.parse(yaml: """
        providers:
          gemini:
            base_url: https://generativelanguage.googleapis.com/v1beta/openai
        commands:
          - name: Gemini
            prompt: gemini.md
            provider: gemini
            model: models/gemini-3.7-flash
        """)

        XCTAssertEqual(config.commands[0].model, "gemini-3.7-flash")
    }

    func testModelsPrefixIsPreservedForOtherProviders() throws {
        let config = try Config.parse(yaml: """
        providers:
          custom:
            base_url: https://example.com/v1
        commands:
          - name: Custom
            prompt: custom.md
            provider: custom
            model: models/custom-model
        """)

        XCTAssertEqual(config.commands[0].model, "models/custom-model")
    }

    func testInvalidReasoningFails() {
        XCTAssertThrowsError(try Config.parse(yaml: """
        providers:
          p:
            base_url: http://localhost:1/v1
        commands:
          - name: X
            prompt: x.md
            model: m
            reasoning: extreme
        """))
    }

    func testSingleProviderIsImplicitDefault() throws {
        let config = try Config.parse(yaml: """
        providers:
          only:
            base_url: http://localhost:1/v1
        commands:
          - name: X
            prompt: x.md
            model: m
        """)
        XCTAssertEqual(try config.resolveProvider(for: config.commands[0]).name, "only")
    }

    func testAmbiguousProviderFails() {
        XCTAssertThrowsError(try Config.parse(yaml: """
        providers:
          a:
            base_url: http://localhost:1/v1
          b:
            base_url: http://localhost:2/v1
        commands:
          - name: X
            prompt: x.md
            model: m
        """))
    }

    func testUnknownProviderReferenceFails() {
        XCTAssertThrowsError(try Config.parse(yaml: """
        providers:
          a:
            base_url: http://localhost:1/v1
        commands:
          - name: X
            prompt: x.md
            provider: nope
            model: m
        """))
    }

    func testDuplicateCommandNameFails() {
        XCTAssertThrowsError(try Config.parse(yaml: """
        providers:
          a:
            base_url: http://localhost:1/v1
        commands:
          - name: X
            prompt: x.md
            model: m
          - name: X
            prompt: y.md
            model: m
        """))
    }

    func testInvalidHotkeyFails() {
        XCTAssertThrowsError(try Config.parse(yaml: """
        providers:
          a:
            base_url: http://localhost:1/v1
        commands:
          - name: X
            hotkey: cmd+definitelynotakey
            prompt: x.md
            model: m
        """))
    }

    func testBrokenYAMLReportsError() {
        XCTAssertThrowsError(try Config.parse(yaml: "providers: [broken")) { error in
            XCTAssertTrue(error is ConfigError)
        }
    }

    func testMissingModelReportsPath() {
        XCTAssertThrowsError(try Config.parse(yaml: """
        providers:
          a:
            base_url: http://localhost:1/v1
        commands:
          - name: X
            prompt: x.md
        """))
    }

    func testUnknownFallbackProviderFails() {
        XCTAssertThrowsError(try Config.parse(yaml: """
        providers:
          a:
            base_url: http://localhost:1/v1
        commands:
          - name: X
            prompt: x.md
            model: m
            fallback_provider: nope
        """))
    }

    func testResolveFallbackDefaultsToPrimaryModel() throws {
        let config = try Config.parse(yaml: """
        providers:
          a:
            base_url: http://localhost:1/v1
          b:
            base_url: http://localhost:2/v1
        default_provider: a
        commands:
          - name: X
            prompt: x.md
            model: m
            fallback_provider: b
          - name: Y
            prompt: y.md
            model: m
            fallback_provider: b
            fallback_model: m2
          - name: Z
            prompt: z.md
            model: m
        """)
        let x = try XCTUnwrap(config.resolveFallback(for: config.commands[0]))
        XCTAssertEqual(x.name, "b")
        XCTAssertEqual(x.model, "m")
        XCTAssertEqual(config.resolveFallback(for: config.commands[1])?.model, "m2")
        XCTAssertNil(config.resolveFallback(for: config.commands[2]))
    }
}
