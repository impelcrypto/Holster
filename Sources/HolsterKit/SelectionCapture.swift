import AppKit
import Carbon.HIToolbox

/// Grabs the selected text of the frontmost app by simulating ⌘C, then
/// restores the previous pasteboard contents.
public enum SelectionCapture {
    public enum CaptureError: LocalizedError {
        case accessibilityDenied
        case nothingCaptured

        public var errorDescription: String? {
            switch self {
            case .accessibilityDenied:
                return "Holster needs Accessibility permission to read the selected text. "
                    + "Grant it in System Settings → Privacy & Security → Accessibility, then try again."
            case .nothingCaptured:
                return "No text selection found in the frontmost app."
            }
        }
    }

    public static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt when not yet granted.
    public static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    public static func capture() async throws -> String {
        guard hasPermission else {
            requestPermission()
            throw CaptureError.accessibilityDenied
        }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount

        postCmdC()

        var text: String?
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != before {
                // One more beat so the source app finishes writing all types.
                try? await Task.sleep(for: .milliseconds(30))
                text = pasteboard.string(forType: .string)
                break
            }
        }

        if pasteboard.changeCount != before {
            restore(pasteboard, items: saved)
        }

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaptureError.nothingCaptured
        }
        return text
    }

    // MARK: - Internals

    /// The hotkey's own modifiers are still physically held here, so the
    /// event's flags are forced to ⌘ only.
    private static func postCmdC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                copy[type] = item.data(forType: type)
            }
            return copy
        }
    }

    private static func restore(_ pasteboard: NSPasteboard, items: [[NSPasteboard.PasteboardType: Data]]) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.enumerated().map { index, entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            if index == 0 {
                // Ask clipboard managers to ignore this write; they already
                // recorded the original the first time around.
                item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
