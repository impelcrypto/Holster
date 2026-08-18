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
        temperature: 0
        stream: true
    """

    func testParsesValidConfig() throws {
        let config = try Config.parse(yaml: validYAML)
        XCTAssertEqual(config.providers.count, 2)
        XCTAssertEqual(config.defaultProvider, "cliproxy")
        XCTAssertEqual(config.commands.count, 1)
        let command = config.commands[0]
        XCTAssertEqual(command.name, "Grammar Teacher")
        XCTAssertEqual(command.model, "gpt-5.6-sol")
        XCTAssertEqual(command.temperature, 0)
        XCTAssertTrue(command.wantsStream)
        let resolved = try config.resolveProvider(for: command)
        XCTAssertEqual(resolved.name, "cliproxy")
        XCTAssertEqual(resolved.provider.baseURL, "http://127.0.0.1:8317/v1")
    }

    func testStreamDefaultsToTrue() throws {
        let config = try Config.parse(yaml: """
        providers:
          p:
            base_url: http://localhost:1/v1
        commands:
          - name: X
            prompt: x.md
            model: m
        """)
        XCTAssertTrue(config.commands[0].wantsStream)
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
}
