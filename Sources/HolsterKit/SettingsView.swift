import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(VisualStyle.storageKey) private var visualStyle = VisualStyle.standard
    @State private var selection: SidebarItem?
    @State private var showSavedToast = false

    enum SidebarItem: Hashable {
        case gettingStarted
        case general
        case speak
        case about
        case command(String)
        case newCommand
    }

    init(store: ConfigStore, initialSelection: SidebarItem? = .gettingStarted) {
        self.store = store
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        // The status bar sits OUTSIDE the split view: safeAreaInset does not
        // reach the AppKit-backed columns, so the detail ScrollView would
        // render its last rows behind the bar.
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $selection) {
                    Label {
                        Text("Getting Started")
                    } icon: {
                        SidebarIcon(systemName: "pencil", top: Color(hex: 0xE07830), bottom: Color(hex: 0xB34A1E))
                    }
                    .tag(SidebarItem.gettingStarted)
                    Label {
                        Text("General")
                    } icon: {
                        SidebarIcon(systemName: "sun.max.fill", top: Color(hex: 0x4FA3FF), bottom: Color(hex: 0x2B6CB0))
                    }
                    .tag(SidebarItem.general)
                    Label {
                        Text("Speak")
                    } icon: {
                        SidebarIcon(systemName: "speaker.wave.2.fill", top: Color(hex: 0xC86DD7), bottom: Color(hex: 0x8E44AD))
                    }
                    .tag(SidebarItem.speak)
                    Section("Prompts") {
                        ForEach(store.config?.commands ?? [], id: \.name) { command in
                            commandRow(command).tag(SidebarItem.command(command.name))
                        }
                    }
                    Section {
                        Label {
                            Text("About")
                        } icon: {
                            SidebarIcon(systemName: "info", top: Color(hex: 0x6EC1FF), bottom: Color(hex: 0x3A8DDE))
                        }
                        .tag(SidebarItem.about)
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
                .toolbar {
                    Button {
                        selection = .newCommand
                    } label: {
                        Label("New Command", systemImage: "plus")
                    }
                }
            } detail: {
                detail
            }
            .overlay(alignment: .bottom) {
                if showSavedToast {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(HolsterTheme.hairline, lineWidth: 1))
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            statusBar
        }
        .frame(minWidth: 760, minHeight: 520)
        // Empty on purpose: reading visualStyle here makes SwiftUI re-render so
        // HolsterTheme picks up the new style.
        .onChange(of: visualStyle) {}
        // The scratch recorder shortcut must not stay registered globally once
        // the settings window closes. KeyboardShortcuts unregisters by VALUE,
        // not by name, so this also kills any command sharing the same combo;
        // reloading re-applies the command hotkeys afterwards.
        .onDisappear {
            KeyboardShortcuts.reset(recorderName)
            store.load()
        }
        .tint(HolsterTheme.accentDeep)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .command(let name):
            CommandEditor(store: store, originalName: name, onSaved: handleSaved)
                .id(name)   // rebuild the editor when another command is picked
        case .newCommand:
            CommandEditor(store: store, originalName: nil, onSaved: handleSaved)
                .id("∅new")
        case .speak:
            SpeakSettingsView(store: store)
        case .about:
            AboutSettingsView()
        case .gettingStarted, .none:
            GettingStartedView(store: store)
        case .general:
            GeneralSettingsView(store: store)
        }
    }

    private func handleSaved(_ name: String) {
        // Empty name means a delete, not a save.
        if name.isEmpty {
            selection = .gettingStarted
        } else {
            selection = .command(name)
            flashSavedToast()
        }
    }

    @ViewBuilder private func commandRow(_ command: CommandConfig) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HolsterTheme.accent)
                .frame(width: 22, height: 22)
                .background(
                    HolsterTheme.accent.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(command.name)
                    .lineLimit(1)
                if let hotkey = command.hotkey, !hotkey.isEmpty {
                    Text(hotkeyDisplay(hotkey))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func flashSavedToast() {
        withAnimation(reduceMotion ? nil : .default) { showSavedToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(reduceMotion ? nil : .default) { showSavedToast = false }
        }
    }

    // Accessibility status lives in General → System Health; this bar only
    // surfaces config errors so they're visible from every tab.
    private var statusBar: some View {
        HStack(spacing: 10) {
            if let error = store.lastError {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Open Config Folder") { NSWorkspace.shared.open(store.directory) }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(HolsterTheme.hairline).frame(height: 1)
        }
    }
}

/// Harper-style 22pt rounded-square sidebar icon with a two-stop gradient.
private struct SidebarIcon: View {
    let systemName: String
    let top: Color
    let bottom: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(
                LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Minimal About screen so the sidebar mirrors Harper's structure.
private struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Holster").font(.system(size: 20, weight: .semibold))
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text("Local-first macOS utility. Your text stays on this Mac except for the LLM calls you trigger.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(HolsterTheme.windowBackground.ignoresSafeArea())
        .navigationTitle("About")
    }
}

/// "cmd+e" from the YAML rendered as the native "⌘E".
private func hotkeyDisplay(_ hotkey: String) -> String {
    (try? HotkeyParser.parse(hotkey)).map { "\($0)" } ?? hotkey
}
