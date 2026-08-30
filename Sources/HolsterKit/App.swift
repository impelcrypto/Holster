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
            MenuBarLabel(store: store, icon: Self.menuBarIcon)
        }

        Window("Holster Settings", id: "settings") {
            SettingsView(store: store)
        }
        .defaultSize(width: 860, height: 580)
    }
}

/// The status-item view is the only view guaranteed to render at launch, so
/// it doubles as the first-run trigger: seeding the example config opens
/// Settings once, where System Health walks through the setup.
private struct MenuBarLabel: View {
    @ObservedObject var store: ConfigStore
    @Environment(\.openWindow) private var openWindow
    let icon: NSImage

    /// Key kept from the retired wizard so existing installs don't re-trigger.
    private static let firstRunShownKey = "onboardingCompleted"

    var body: some View {
        Group {
            if store.lastError == nil {
                Image(nsImage: icon)
            } else {
                Image(systemName: "exclamationmark.triangle")
            }
        }
        .task { openSettingsIfFirstRun() }
        .onChange(of: store.didSeedExamples) { openSettingsIfFirstRun() }
    }

    private func openSettingsIfFirstRun() {
        guard store.didSeedExamples,
              !UserDefaults.standard.bool(forKey: Self.firstRunShownKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.firstRunShownKey)
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory policy also when launched via `swift run` (no Info.plist).
        NSApp.setActivationPolicy(.accessory)
        // App-wide: also reaches AppKit-backed controls (recorder, alerts) that
        // per-view SwiftUI colorScheme forcing would miss.
        AppearancePreference.stored.apply()
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
