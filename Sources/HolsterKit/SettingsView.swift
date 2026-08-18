import AppKit
import KeyboardShortcuts
import SwiftUI

private let recorderName = KeyboardShortcuts.Name("settings.recorder.scratch")

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @State private var selectedCommand: String?
    @State private var showSavedToast = false

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
                onSaved: { name in
                    // Empty name means a delete, not a save.
                    selectedCommand = name.isEmpty ? nil : name
                    if !name.isEmpty { flashSavedToast() }
                })
            // Rebuild the editor whenever another command is picked.
            .id(selectedCommand ?? "\u{2205}new")
        }
        .frame(minWidth: 760, minHeight: 520)
        // Overlay must come before the safeAreaInset so the toast sits above
        // the status bar instead of behind it.
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
        .safeAreaInset(edge: .bottom) { statusBar }
        .onAppear {
            if selectedCommand == nil {
                selectedCommand = store.config?.commands.first?.name
            }
        }
        // The scratch recorder shortcut must not stay registered globally once
        // the settings window closes. KeyboardShortcuts unregisters by VALUE,
        // not by name, so this also kills any command sharing the same combo;
        // reloading re-applies the command hotkeys afterwards.
        .onDisappear {
            KeyboardShortcuts.reset(recorderName)
            store.load()
        }
    }

    private func flashSavedToast() {
        withAnimation { showSavedToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSavedToast = false }
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
    @State private var modelsError: String?
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    private var providerNames: [String] {
        var names = Set((store.config?.providers.keys).map(Array.init) ?? [])
        names.insert(ProviderPreset.openCodeGo)
        names.insert(ProviderPreset.custom)
        return names.sorted()
    }

    private var isPresetProvider: Bool {
        draft.provider == ProviderPreset.openCodeGo || draft.provider == ProviderPreset.custom
    }

    private func providerLabel(_ name: String) -> String {
        switch name {
        case ProviderPreset.openCodeGo: return "OpenCode Go"
        case ProviderPreset.custom: return "Custom Endpoint"
        default: return name
        }
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
                Picker("Provider", selection: providerBinding) {
                    ForEach(providerNames, id: \.self) { Text(providerLabel($0)).tag($0) }
                }
                if draft.provider == ProviderPreset.custom {
                    TextField("Base URL", text: $draft.baseURL,
                              prompt: Text("https://openrouter.ai/api/v1"))
                        .font(.callout.monospaced())
                }
                if isPresetProvider {
                    TextField("API Key", text: $draft.apiKey, prompt: Text("sk-…"))
                        .font(.callout.monospaced())
                        .onSubmit { fetchModels() }
                }
                Picker("Model", selection: $draft.model) {
                    if !models.contains(draft.model), !draft.model.isEmpty {
                        Text(draft.model).tag(draft.model)
                    }
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                if let modelsError {
                    HStack {
                        Text("Couldn't load models: \(modelsError)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                        Spacer()
                        Button("Retry") { fetchModels() }
                            .controlSize(.small)
                    }
                }
                Picker("Reasoning", selection: $draft.reasoning) {
                    if draft.provider != ProviderPreset.openCodeGo {
                        Text("None").tag("")
                    }
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }
                Toggle("Auto-copy selected text in result window", isOn: $draft.copyOnSelect)
            }
            Section("Prompt — {selection} is replaced with the selected text") {
                TextEditor(text: $draft.promptText)
                    .font(.body.monospaced())
                    .frame(minHeight: 220)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(originalName ?? "New Command")
        .toolbar {
            if originalName != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { save() } label: {
                    Text("Save").padding(.horizontal, 10)
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
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
        syncProviderFields()
        fetchModels()
    }

    /// Picker writes go through here so only USER changes reset the model;
    /// loadDraft assigns draft directly and must keep the saved model.
    private var providerBinding: Binding<String> {
        Binding(
            get: { draft.provider },
            set: { name in
                guard name != draft.provider else { return }
                draft.provider = name
                draft.model = ""
                // Reasoning must not carry over either: "low" left behind by
                // OpenCode Go turns THINKING ON for Ollama's hybrid models.
                draft.reasoning = name == ProviderPreset.openCodeGo ? "low" : ""
                syncProviderFields()
                fetchModels()
            })
    }

    /// Refill endpoint fields when the provider changes: saved entry first,
    /// then the preset default, so a save never wipes a stored key.
    private func syncProviderFields() {
        if let saved = store.config?.providers[draft.provider] {
            draft.baseURL = saved.baseURL
            draft.apiKey = saved.apiKey ?? ""
        } else {
            draft.baseURL = draft.provider == ProviderPreset.openCodeGo
                ? ProviderPreset.openCodeGoBaseURL : ""
            draft.apiKey = ""
        }
        // No "None" on OpenCode Go (its models all think by default).
        if draft.provider == ProviderPreset.openCodeGo, draft.reasoning.isEmpty {
            draft.reasoning = "low"
        }
    }

    private func fetchModels() {
        models = []
        modelsError = nil
        let baseURL: String
        let apiKey: String?
        if isPresetProvider {
            baseURL = draft.provider == ProviderPreset.openCodeGo
                ? ProviderPreset.openCodeGoBaseURL : draft.baseURL
            apiKey = draft.apiKey
        } else if let provider = store.config?.providers[draft.provider] {
            baseURL = provider.baseURL
            apiKey = provider.apiKey
        } else {
            return
        }
        guard !baseURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Go always rejects keyless requests; don't flash a 401 before a key is typed.
        if draft.provider == ProviderPreset.openCodeGo, draft.apiKey.isEmpty { return }
        let requestedProvider = draft.provider
        Task { @MainActor in
            do {
                let fetched = try await LLMClient.listModels(baseURL: baseURL, apiKey: apiKey)
                guard draft.provider == requestedProvider else { return }
                models = fetched
                if draft.model.isEmpty, let first = fetched.first {
                    draft.model = first
                }
            } catch {
                guard draft.provider == requestedProvider else { return }
                modelsError = error.localizedDescription
            }
        }
    }

    private func save() {
        do {
            try store.saveCommand(originalName: originalName, draft: draft)
            onSaved(draft.name)
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
