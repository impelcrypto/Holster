import Foundation
import KeyboardShortcuts

/// Registers global hotkeys from the YAML config. YAML is the single source
/// of truth: every reload wipes what KeyboardShortcuts persisted to
/// UserDefaults and re-applies the parsed shortcuts.
@MainActor
public final class HotkeyManager {
    public var onTrigger: ((CommandConfig) -> Void)?

    private var registered: [KeyboardShortcuts.Name] = []

    public init() {}

    public func apply(config: Config) {
        KeyboardShortcuts.reset(registered)
        KeyboardShortcuts.removeAllHandlers()
        registered.removeAll()

        for command in config.commands {
            guard let hotkeyString = command.hotkey,
                  !hotkeyString.isEmpty,
                  let shortcut = try? HotkeyParser.parse(hotkeyString)
            else { continue }

            let name = KeyboardShortcuts.Name("command.\(command.name)")
            KeyboardShortcuts.setShortcut(shortcut, for: name)
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                self?.onTrigger?(command)
            }
            registered.append(name)
        }
    }
}
