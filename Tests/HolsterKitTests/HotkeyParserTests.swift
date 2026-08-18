import XCTest
import KeyboardShortcuts
@testable import HolsterKit

final class HotkeyParserTests: XCTestCase {
    func testParsesCmdShiftG() throws {
        let shortcut = try HotkeyParser.parse("cmd+shift+g")
        XCTAssertEqual(shortcut.key, .g)
        XCTAssertTrue(shortcut.modifiers.contains(.command))
        XCTAssertTrue(shortcut.modifiers.contains(.shift))
        XCTAssertFalse(shortcut.modifiers.contains(.option))
    }

    func testParsesAliases() throws {
        XCTAssertEqual(try HotkeyParser.parse("command+alt+f5").key, .f5)
        XCTAssertEqual(try HotkeyParser.parse("ctrl+space").key, .space)
    }

    func testIsCaseInsensitiveAndTrimsSpaces() throws {
        let shortcut = try HotkeyParser.parse("Cmd + Shift + G")
        XCTAssertEqual(shortcut.key, .g)
    }

    func testRejectsUnknownKey() {
        XCTAssertThrowsError(try HotkeyParser.parse("cmd+nosuchkey"))
    }

    func testRejectsUnknownModifier() {
        XCTAssertThrowsError(try HotkeyParser.parse("hyper+g"))
    }

    func testRejectsBareKeyWithoutModifier() {
        XCTAssertThrowsError(try HotkeyParser.parse("g"))
    }

    func testFormatUsesCanonicalModifierOrder() throws {
        XCTAssertEqual(try HotkeyParser.format(HotkeyParser.parse("cmd+shift+g")), "shift+cmd+g")
        XCTAssertEqual(try HotkeyParser.format(HotkeyParser.parse("cmd+period")), "cmd+period")
        XCTAssertEqual(
            try HotkeyParser.format(HotkeyParser.parse("shift+ctrl+opt+cmd+f12")),
            "ctrl+opt+shift+cmd+f12")
    }

    func testFormatOutputParsesBackToSameShortcut() throws {
        let original = try HotkeyParser.parse("cmd+shift+g")
        let formatted = try XCTUnwrap(HotkeyParser.format(original))
        XCTAssertEqual(try HotkeyParser.parse(formatted), original)
    }
}
