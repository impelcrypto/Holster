import AppKit
import SwiftUI

/// Spotlight-style floating panel: becomes key for Esc/⌘↩ handling but never
/// activates the app, so the user's editor keeps focus.
final class ResultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Once the user drags or resizes the panel, that frame wins over the
    /// automatic placement/sizing for the rest of the session.
    private var userMovedPanel = false
    private var userResizedPanel = false
    private var programmaticFrameChange = false

    /// Per-command copy_on_select: a finished drag selection inside the panel
    /// copies the selected text (normalized to plain text).
    var autoCopyOnSelect = false
    var onAutoCopy: (() -> Void)?
    private var mouseMonitor: Any?
    private var draggingSelection = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable, .closable],
            backing: .buffered,
            defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        // Normal level: frontmost when presented, but clicking another window
        // sends the panel behind it instead of pinning it above everything.
        level = .normal
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        NotificationCenter.default.addObserver(
            self, selector: #selector(frameDidMove), name: NSWindow.didMoveNotification, object: self)
        NotificationCenter.default.addObserver(
            self, selector: #selector(frameDidResize), name: NSWindow.didResizeNotification, object: self)

        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleMouse(event)
            return event
        }
    }

    private func handleMouse(_ event: NSEvent) {
        guard event.window === self else { return }
        switch event.type {
        case .leftMouseDown:
            draggingSelection = false
        case .leftMouseDragged:
            draggingSelection = true
        case .leftMouseUp:
            if draggingSelection, autoCopyOnSelect {
                draggingSelection = false
                copySelectionIfAny()
            }
        default:
            break
        }
    }

    /// Fires the responder-chain copy after the drag; if something landed on
    /// the pasteboard, rewrite it as plain text and report success.
    private func copySelectionIfAny() {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard pasteboard.changeCount != before,
                      let plain = pasteboard.string(forType: .string),
                      !plain.isEmpty
                else { return }
                pasteboard.clearContents()
                pasteboard.setString(plain, forType: .string)
                self?.onAutoCopy?()
            }
        }
    }

    @objc private func frameDidMove() {
        if !programmaticFrameChange && isVisible { userMovedPanel = true }
    }

    @objc private func frameDidResize() {
        if !programmaticFrameChange && isVisible { userResizedPanel = true }
    }

    /// Esc
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    func present<Content: View>(_ view: Content) {
        contentView = NSHostingView(rootView: view)
        if !userMovedPanel {
            withProgrammaticFrameChange { positionOnActiveScreen() }
        }
        makeKeyAndOrderFront(nil)
        // Our app is never active, so plain orderFront can leave a
        // normal-level window behind the active app's windows.
        orderFrontRegardless()
    }

    /// Grows or shrinks with the markdown content, top edge pinned, clamped
    /// to 70% of the screen; beyond that the content scrolls.
    func adjustContentHeight(_ contentHeight: CGFloat) {
        guard !userResizedPanel else { return }
        let chrome: CGFloat = 92  // header + footer + dividers
        let screenHeight = (screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let target = min(max(contentHeight + chrome, 220), screenHeight * 0.7)
        guard abs(target - frame.height) > 4 else { return }
        var newFrame = frame
        newFrame.origin.y = newFrame.maxY - target
        newFrame.size.height = target
        withProgrammaticFrameChange { setFrame(newFrame, display: true) }
    }

    private func withProgrammaticFrameChange(_ body: () -> Void) {
        programmaticFrameChange = true
        body()
        programmaticFrameChange = false
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - visible.height * 0.12 - size.height)
        setFrameOrigin(origin)
    }
}
