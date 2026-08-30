import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: SidebarItem?
    @State private var showSavedToast = false

    enum SidebarItem: Hashable {
        case general
        case speak
        case command(String)
        case newCommand
    }

    init(store: ConfigStore, initialSelection: SidebarItem? = .general) {
        self.store = store
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape")
                    .tag(SidebarItem.general)
                Label("Speak", systemImage: "speaker.wave.2.fill")
                    .tag(SidebarItem.speak)
                Section("Prompts") {
                    ForEach(store.config?.commands ?? [], id: \.name) { command in
                        commandRow(command).tag(SidebarItem.command(command.name))
                    }
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
        .frame(minWidth: 760, minHeight: 520)
        // Overlay must come before the safeAreaInset so the toast sits above
        // the status bar instead of behind it.
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
        .safeAreaInset(edge: .bottom) { statusBar }
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
                .id("\u{2205}new")
        case .speak:
            SpeakSettingsView(store: store)
        case .general, .none:
            GeneralSettingsView(store: store)
        }
    }

    private func handleSaved(_ name: String) {
        // Empty name means a delete, not a save.
        if name.isEmpty {
            selection = .general
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

/// "cmd+e" from the YAML rendered as the native "⌘E".
private func hotkeyDisplay(_ hotkey: String) -> String {
    (try? HotkeyParser.parse(hotkey)).map { "\($0)" } ?? hotkey
}
