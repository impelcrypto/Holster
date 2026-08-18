import AppKit
import KeyboardShortcuts

/// Converts between config strings like "cmd+shift+g" and
/// KeyboardShortcuts.Shortcut values.
public enum HotkeyParser {
    public struct ParseError: LocalizedError, Equatable {
        public let message: String
        public var errorDescription: String? { message }
    }

    private static let modifierNames: [String: NSEvent.ModifierFlags] = [
        "cmd": .command, "command": .command,
        "shift": .shift,
        "opt": .option, "option": .option, "alt": .option,
        "ctrl": .control, "control": .control,
    ]

    private static let keyNames: [String: KeyboardShortcuts.Key] = {
        var map: [String: KeyboardShortcuts.Key] = [
            "0": .zero, "1": .one, "2": .two, "3": .three, "4": .four,
            "5": .five, "6": .six, "7": .seven, "8": .eight, "9": .nine,
            "a": .a, "b": .b, "c": .c, "d": .d, "e": .e, "f": .f, "g": .g,
            "h": .h, "i": .i, "j": .j, "k": .k, "l": .l, "m": .m, "n": .n,
            "o": .o, "p": .p, "q": .q, "r": .r, "s": .s, "t": .t, "u": .u,
            "v": .v, "w": .w, "x": .x, "y": .y, "z": .z,
            "space": .space, "tab": .tab, "return": .return, "enter": .return,
            "escape": .escape, "esc": .escape, "delete": .delete,
            "up": .upArrow, "down": .downArrow, "left": .leftArrow, "right": .rightArrow,
            "minus": .minus, "equal": .equal, "comma": .comma, "period": .period,
            "slash": .slash, "backslash": .backslash, "quote": .quote,
            "semicolon": .semicolon, "leftbracket": .leftBracket, "rightbracket": .rightBracket,
        ]
        let fKeys: [KeyboardShortcuts.Key] = [
            .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
        ]
        for (index, key) in fKeys.enumerated() {
            map["f\(index + 1)"] = key
        }
        return map
    }()

    public static func parse(_ string: String) throws -> KeyboardShortcuts.Shortcut {
        let parts = string.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last, !keyName.isEmpty else {
            throw ParseError(message: "Empty hotkey")
        }
        guard let key = keyNames[keyName] else {
            throw ParseError(message: "Unknown key \"\(keyName)\" in hotkey \"\(string)\"")
        }
        var modifiers: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            guard let flag = modifierNames[part] else {
                throw ParseError(message: "Unknown modifier \"\(part)\" in hotkey \"\(string)\"")
            }
            modifiers.insert(flag)
        }
        guard !modifiers.isEmpty else {
            throw ParseError(message: "Hotkey \"\(string)\" needs at least one modifier (cmd/shift/opt/ctrl)")
        }
        return KeyboardShortcuts.Shortcut(key, modifiers: modifiers)
    }

    /// Inverse of parse, used when the GUI writes a recorded shortcut back to
    /// YAML. Returns nil for keys outside our naming table.
    public static func format(_ shortcut: KeyboardShortcuts.Shortcut) -> String? {
        guard let key = shortcut.key,
              let keyName = keyNames.first(where: { $0.value == key })?.key
        else { return nil }
        var parts: [String] = []
        if shortcut.modifiers.contains(.control) { parts.append("ctrl") }
        if shortcut.modifiers.contains(.option) { parts.append("opt") }
        if shortcut.modifiers.contains(.shift) { parts.append("shift") }
        if shortcut.modifiers.contains(.command) { parts.append("cmd") }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }
}
