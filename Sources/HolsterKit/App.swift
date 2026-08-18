import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppState {
    static let shared = AppState()

    let store = ConfigStore()
    let hotkeys = HotkeyManager()
    let speaker = Speaker()
    private(set) lazy var runner = CommandRunner(store: store, speaker: speaker)

    private init() {}

    func start() {
        store.onReload = { [weak self] config in
            self?.hotkeys.apply(config: config)
        }
        hotkeys.onTrigger = { [weak self] command in
            self?.runner.run(command)
        }
        store.bootstrapAndLoad()
    }
}

struct HolsterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var store = AppState.shared.store

    // Template image: the menu bar recolors it for light/dark/highlight.
    private static let menuBarIcon: NSImage = {
        guard let image = Bundle.module.image(forResource: "MenuBarIcon") else {
            fatalError("MenuBarIcon.png missing from HolsterKit bundle")
        }
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            if store.lastError == nil {
                Image(nsImage: Self.menuBarIcon)
            } else {
                Image(systemName: "exclamationmark.triangle")
            }
        }

        Window("Holster Settings", id: "settings") {
            SettingsView(store: store)
        }
        .defaultSize(width: 860, height: 580)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory policy also when launched via `swift run` (no Info.plist).
        NSApp.setActivationPolicy(.accessory)
        // App-wide dark theme: also reaches AppKit-backed controls (recorder,
        // alerts) that per-view SwiftUI colorScheme forcing would miss.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        AppState.shared.start()
    }
}

struct MenuContent: View {
    @ObservedObject var store: ConfigStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let error = store.lastError {
            Text(error)
        }
        ForEach(store.config?.commands ?? []) { command in
            Button {
                AppState.shared.runner.run(command)
            } label: {
                if let hotkey = command.hotkey {
                    Text("\(command.name)   \(hotkey)")
                } else {
                    Text(command.name)
                }
            }
        }
        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button("Reload Config") { store.load() }
        Button("Open Config Folder") {
            NSWorkspace.shared.open(store.directory)
        }
        Divider()
        LaunchAtLoginToggle()
        Divider()
        Button("Quit Holster") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// SMAppService only works when running from a real .app bundle; the toggle
/// hides itself under `swift run`.
private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        if Bundle.main.bundlePath.hasSuffix(".app") {
            Toggle("Launch at Login", isOn: $enabled)
                .onChange(of: enabled) {
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        enabled = SMAppService.mainApp.status == .enabled
                    }
                }
        }
    }
}
