import AppKit
import KeyboardShortcuts
import SwiftUI

private let recorderName = KeyboardShortcuts.Name("settings.recorder.scratch")

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @State private var selectedCommand: String?

    var body: some View {
        NavigationSplitView {
            List(store.config?.commands ?? [], id: \.name, selection: $selectedCommand) { command in
                Text(command.name)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200)
            .toolbar {
                Button {
                    selectedCommand = nil
                } label: {
                    Label("New Command", systemImage: "plus")
                }
            }
        } detail: {
            CommandEditor(
                store: store,
                originalName: selectedCommand,
                onSaved: { name in selectedCommand = name })
            // Rebuild the editor whenever another command is picked.
            .id(selectedCommand ?? "\u{2205}new")
        }
        .frame(minWidth: 760, minHeight: 520)
        .safeAreaInset(edge: .bottom) { statusBar }
        // The scratch recorder shortcut must not stay registered globally once
        // the settings window closes. KeyboardShortcuts unregisters by VALUE,
        // not by name, so this also kills any command sharing the same combo;
        // reloading re-applies the command hotkeys afterwards.
        .onDisappear {
            KeyboardShortcuts.reset(recorderName)
            store.load()
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Image(systemName: SelectionCapture.hasPermission ? "checkmark.circle" : "xmark.circle")
                .foregroundStyle(SelectionCapture.hasPermission ? .green : .orange)
            Text(SelectionCapture.hasPermission
                ? "Accessibility permission granted"
                : "Accessibility permission required for selection capture")
                .font(.caption)
            if !SelectionCapture.hasPermission {
                Button("Grant…") { SelectionCapture.requestPermission() }
                    .controlSize(.small)
            }
            Spacer()
            Button("Open Config Folder") { NSWorkspace.shared.open(store.directory) }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct CommandEditor: View {
    @ObservedObject var store: ConfigStore
    let originalName: String?
    let onSaved: (String) -> Void

    @State private var draft = ConfigStore.CommandDraft()
    @State private var models: [String] = []
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var showSavedToast = false

    private var providerNames: [String] {
        (store.config?.providers.keys).map(Array.init)?.sorted() ?? []
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("Grammar Teacher"))
                LabeledContent("Hotkey") {
                    KeyboardShortcuts.Recorder(for: recorderName) { shortcut in
                        draft.hotkey = shortcut.flatMap(HotkeyParser.format) ?? ""
                        // Recording replaced the scratch value, which
                        // value-unregisters any command using the old combo.
                        store.load()
                    }
                }
            }
            Section {
                Picker("Provider", selection: $draft.provider) {
                    ForEach(providerNames, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: draft.provider) { fetchModels() }
                Picker("Model", selection: $draft.model) {
                    if !models.contains(draft.model), !draft.model.isEmpty {
                        Text(draft.model).tag(draft.model)
                    }
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                TextField("Model id (free form)", text: $draft.model)
                    .font(.callout.monospaced())
                TextField("Temperature", text: $draft.temperatureText,
                          prompt: Text("provider default"))
                Toggle("Stream response", isOn: $draft.stream)
                Toggle("Auto-copy selected text in result window", isOn: $draft.copyOnSelect)
            }
            Section("Prompt — {selection} is replaced with the selected text") {
                TextEditor(text: $draft.promptText)
                    .font(.body.monospaced())
                    .frame(minHeight: 220)
            }
        }
        .formStyle(.grouped)
        .overlay(alignment: .bottom) {
            if showSavedToast {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .navigationTitle(originalName ?? "New Command")
        .toolbar {
            if originalName != nil {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .alert("Delete \"\(originalName ?? "")\"?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The prompt file stays in prompts/ so nothing is lost.")
        }
        .alert("Cannot save", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: loadDraft)
    }

    private func loadDraft() {
        if let originalName, let command = store.command(named: originalName) {
            draft = store.draft(for: command)
        } else {
            draft = ConfigStore.CommandDraft(
                provider: store.config?.defaultProvider ?? providerNames.first ?? "",
                promptText: "You are a helpful assistant.\n\n{selection}\n")
        }
        KeyboardShortcuts.setShortcut(
            draft.hotkey.isEmpty ? nil : try? HotkeyParser.parse(draft.hotkey),
            for: recorderName)
        // Seeding the scratch value-unregisters whatever combo it held before
        // (e.g. the previously selected command's hotkey); re-assert them all.
        store.load()
        fetchModels()
    }

    private func fetchModels() {
        models = []
        guard let provider = store.config?.providers[draft.provider] else { return }
        Task { @MainActor in
            if let fetched = try? await LLMClient.listModels(
                baseURL: provider.baseURL, apiKey: provider.apiKey) {
                models = fetched
            }
        }
    }

    private func save() {
        do {
            try store.saveCommand(originalName: originalName, draft: draft)
            onSaved(draft.name)
            withAnimation { showSavedToast = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { showSavedToast = false }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        guard let originalName else { return }
        do {
            try store.deleteCommand(named: originalName)
            onSaved("")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
