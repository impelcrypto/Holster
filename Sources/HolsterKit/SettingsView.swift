import AppKit
import KeyboardShortcuts
import SwiftUI

private let recorderName = KeyboardShortcuts.Name("settings.recorder.scratch")

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @State private var selection: SidebarItem? = .general
    @State private var showSavedToast = false

    enum SidebarItem: Hashable {
        case general
        case speak
        case command(String)
        case newCommand
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
            GeneralSettingsView()
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
        withAnimation { showSavedToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSavedToast = false }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(SelectionCapture.hasPermission ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(SelectionCapture.hasPermission
                ? "Accessibility permission granted"
                : "Accessibility permission required for selection capture")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            if !SelectionCapture.hasPermission {
                Button("Grant…") { SelectionCapture.requestPermission() }
                    .buttonStyle(GhostButtonStyle())
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

private func reasoningOptions(showNone: Bool) -> [(label: String, value: String)] {
    (showNone ? [("None", "")] : []) + [("Low", "low"), ("Medium", "medium"), ("High", "high")]
}

/// "cmd+e" from the YAML rendered as the native "⌘E".
private func hotkeyDisplay(_ hotkey: String) -> String {
    (try? HotkeyParser.parse(hotkey)).map { "\($0)" } ?? hotkey
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                HolsterTheme.card,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(HolsterTheme.hairline, lineWidth: 1))
    }
}

struct SettingRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(HolsterTheme.hairline)
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

/// Uppercase section header with an optional inline note, matching the editor.
struct SettingsSection<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 2)
            content
        }
    }
}

private struct InsetFieldChrome: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(width: 280)
            .background(
                HolsterTheme.inset,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        focused ? HolsterTheme.accent.opacity(0.6) : HolsterTheme.hairline,
                        lineWidth: 1))
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

extension View {
    fileprivate func insetField(focused: Bool) -> some View {
        modifier(InsetFieldChrome(focused: focused))
    }
}

/// Custom segmented control: amber pill on the selected chip.
struct SegmentedPicker: View {
    let options: [(label: String, value: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.black.opacity(0.8) : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            if selected {
                                Capsule().fill(HolsterTheme.accentGradient)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(HolsterTheme.inset, in: Capsule())
        .overlay(Capsule().strokeBorder(HolsterTheme.hairline, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

private struct CommandEditor: View {
    @ObservedObject var store: ConfigStore
    let originalName: String?
    let onSaved: (String) -> Void

    @State private var draft = ConfigStore.CommandDraft()
    /// Snapshot taken after load; Save stays disabled until the draft differs.
    @State private var savedDraft: ConfigStore.CommandDraft?
    @State private var models: [String] = []
    @State private var modelsError: String?
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var advancedExpanded = false
    @State private var fallbackModels: [String] = []

    private enum Field { case name, baseURL, apiKey, prompt }
    @FocusState private var focus: Field?

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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Command") {
                    SettingsCard {
                        SettingRow(label: "Name") {
                            TextField("", text: $draft.name, prompt: Text("Grammar Teacher"))
                                .font(.system(size: 13))
                                .focused($focus, equals: .name)
                                .insetField(focused: focus == .name)
                        }
                        RowDivider()
                        SettingRow(label: "Hotkey") {
                            KeyboardShortcuts.Recorder(for: recorderName) { shortcut in
                                draft.hotkey = shortcut.flatMap(HotkeyParser.format) ?? ""
                                // Recording replaced the scratch value, which
                                // value-unregisters any command using the old combo.
                                store.load()
                            }
                        }
                    }
                }
                section("Provider & Model") {
                    SettingsCard {
                        SettingRow(label: "Provider") {
                            Picker("", selection: providerBinding) {
                                ForEach(providerNames, id: \.self) {
                                    Text(providerLabel($0)).tag($0)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        if draft.provider == ProviderPreset.custom {
                            RowDivider()
                            SettingRow(label: "Base URL") {
                                TextField("", text: $draft.baseURL,
                                          prompt: Text("https://openrouter.ai/api/v1"))
                                    .font(.system(size: 12, design: .monospaced))
                                    .focused($focus, equals: .baseURL)
                                    .insetField(focused: focus == .baseURL)
                            }
                        }
                        if isPresetProvider {
                            RowDivider()
                            SettingRow(label: "API Key") {
                                TextField("", text: $draft.apiKey, prompt: Text("sk-…"))
                                    .font(.system(size: 12, design: .monospaced))
                                    .focused($focus, equals: .apiKey)
                                    .onSubmit { fetchModels() }
                                    .insetField(focused: focus == .apiKey)
                            }
                        }
                        RowDivider()
                        SettingRow(label: "Model") {
                            Picker("", selection: $draft.model) {
                                if !models.contains(draft.model), !draft.model.isEmpty {
                                    Text(draft.model).tag(draft.model)
                                }
                                ForEach(models, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        if let modelsError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                                Text("Couldn't load models: \(modelsError)")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.orange)
                                    .lineLimit(2)
                                Spacer()
                                Button("Retry") { fetchModels() }
                                    .buttonStyle(GhostButtonStyle())
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                        }
                        RowDivider()
                        SettingRow(label: "Reasoning") {
                            SegmentedPicker(
                                options: reasoningOptions(
                                    showNone: draft.provider != ProviderPreset.openCodeGo),
                                selection: $draft.reasoning)
                        }
                        RowDivider()
                        SettingRow(label: "Auto-copy selected text in result window") {
                            Toggle("", isOn: $draft.copyOnSelect)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                }
                advancedSection
                section("Prompt", note: "{selection} is replaced with the selected text") {
                    TextEditor(text: $draft.promptText)
                        .font(.system(size: 12.5, design: .monospaced))
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .focused($focus, equals: .prompt)
                        .padding(10)
                        .frame(minHeight: 240)
                        .background(
                            HolsterTheme.inset,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    focus == .prompt
                                        ? HolsterTheme.accent.opacity(0.6) : HolsterTheme.hairline,
                                    lineWidth: 1))
                }
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(HolsterTheme.windowBackground.ignoresSafeArea())
        .navigationTitle(originalName ?? "New Command")
        .toolbar {
            // One item for both buttons: separate placements get squeezed
            // into a shared glass group and the pills overlap.
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 10) {
                    if originalName != nil {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(GhostButtonStyle(tint: Color(hex: 0xFF6B5E)))
                        .help("Delete command")
                    }
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 5) {
                            Text("Save")
                            Text("⌘S")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.45))
                        }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(AccentButtonStyle())
                    .disabled(draft == savedDraft)
                }
                // Breathing room against the toolbar's glass group edges;
                // the group hugs the trailing pill tighter than the leading one.
                .padding(.leading, 6)
                .padding(.trailing, 12)
            }
        }
        // Plain-style TextFields only commit their binding on end-editing;
        // mirror keystrokes so the Save dirty-check tracks live text.
        .onReceive(NotificationCenter.default.publisher(
            for: NSControl.textDidChangeNotification)
        ) { note in
            guard let field = note.object as? NSTextField else { return }
            switch focus {
            case .name: draft.name = field.stringValue
            case .baseURL: draft.baseURL = field.stringValue
            case .apiKey: draft.apiKey = field.stringValue
            default: break
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

    /// Accordion: header toggles the fallback card, collapsed by default
    /// unless the command already has a fallback configured.
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { advancedExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(advancedExpanded ? 90 : 0))
                        Text("ADVANCED")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.secondary)
                    Text("Fallback is used when the provider is down")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
            if advancedExpanded {
                SettingsCard {
                    SettingRow(label: "Fallback Provider") {
                        Picker("", selection: fallbackProviderBinding) {
                            Text("None").tag("")
                            ForEach(configuredProviderNames, id: \.self) {
                                Text(providerLabel($0)).tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    if !draft.fallbackProvider.isEmpty {
                        RowDivider()
                        SettingRow(label: "Fallback Model") {
                            Picker("", selection: $draft.fallbackModel) {
                                Text("Same as primary").tag("")
                                if !fallbackModels.contains(draft.fallbackModel),
                                   !draft.fallbackModel.isEmpty {
                                    Text(draft.fallbackModel).tag(draft.fallbackModel)
                                }
                                ForEach(fallbackModels, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }
        }
    }

    /// Only providers already saved in config.yaml qualify as fallbacks; the
    /// unsaved presets have no endpoint to fall back to yet.
    private var configuredProviderNames: [String] {
        ((store.config?.providers.keys).map(Array.init) ?? []).sorted()
    }

    private var fallbackProviderBinding: Binding<String> {
        Binding(
            get: { draft.fallbackProvider },
            set: { name in
                guard name != draft.fallbackProvider else { return }
                draft.fallbackProvider = name
                draft.fallbackModel = ""
                fetchFallbackModels()
            })
    }

    // ponytail: fetch failures stay silent — "Same as primary" keeps the
    // picker usable; add an error row like the primary's if users get stuck.
    private func fetchFallbackModels() {
        fallbackModels = []
        guard let provider = store.config?.providers[draft.fallbackProvider] else { return }
        let requested = draft.fallbackProvider
        Task { @MainActor in
            guard let fetched = try? await LLMClient.listModels(
                baseURL: provider.baseURL, apiKey: provider.apiKey),
                draft.fallbackProvider == requested else { return }
            fallbackModels = fetched
        }
    }

    private func section(
        _ title: String, note: String? = nil, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 2)
            content()
        }
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
        savedDraft = draft
        advancedExpanded = !draft.fallbackProvider.isEmpty
        fetchModels()
        fetchFallbackModels()
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
            // Same-name saves don't rebuild the editor, so re-disable here.
            savedDraft = draft
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
