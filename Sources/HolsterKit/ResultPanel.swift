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

    /// Fires on every close (Esc, ⌘↩ copy, red button) so the owner can stop
    /// the in-flight stream instead of letting it burn tokens unseen.
    var onClose: (() -> Void)?
    private var mouseMonitor: Any?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable, .closable],
            backing: .buffered,
            defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // SwiftUI hands the window every pixel that isn't a glyph, so this
        // dragged the panel whenever a selection started a hair off the text.
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        // Transparent window: the content's NSVisualEffectView supplies the
        // blurred backdrop; titled windows still clip to rounded corners.
        isOpaque = false
        backgroundColor = .clear
        // Normal level: frontmost when presented, but clicking another window
        // sends the panel behind it instead of pinning it above everything.
        level = .normal
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        NotificationCenter.default.addObserver(
            self, selector: #selector(frameDidMove), name: NSWindow.didMoveNotification, object: self)
        NotificationCenter.default.addObserver(
            self, selector: #selector(frameDidResize), name: NSWindow.didResizeNotification, object: self)

        // The app is never active, so AppKit spends the first click on an
        // unfocused panel making it key. Taking key here delivers that click.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            if let self, event.window === self, !self.isKeyWindow { self.makeKey() }
            return event
        }
    }

    deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
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

    override func close() {
        onClose?()
        super.close()
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
        // header + footer + dividers, plus the titlebar safe-area inset that
        // fullSizeContentView pushes the content below.
        let chrome: CGFloat = 92 + (contentView?.safeAreaInsets.top ?? 28)
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
