import AppKit
import KeyboardShortcuts
import SwiftUI

/// Shared scratch recorder name: SettingsView resets it on disappear.
let recorderName = KeyboardShortcuts.Name("settings.recorder.scratch")

private func reasoningOptions(showNone: Bool) -> [(label: String, value: String)] {
    (showNone ? [("None", "")] : []) + [("Low", "low"), ("Medium", "medium"), ("High", "high")]
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

private enum CredentialConnectionState: Equatable {
    case idle
    case checking
    case connected
    case failed(String)
}

private struct CredentialStatus: View {
    let state: CredentialConnectionState
    let saved: Bool
    let savedLabel: String
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        if saved || state != .idle {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    statusIcon
                    Text(statusLabel)
                        .font(.system(size: 11.5))
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .failed(let detail) = state {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if case .failed = state {
                        Button("Retry", action: onRetry)
                            .buttonStyle(GhostButtonStyle())
                    }
                    Spacer()
                    if saved {
                        Button("Remove API Key", role: .destructive, action: onRemove)
                            .buttonStyle(GhostButtonStyle(tint: .red))
                    }
                }
            }
            .frame(width: 280, alignment: .leading)
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "key.fill")
                .foregroundStyle(.secondary)
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var statusLabel: String {
        switch state {
        case .idle:
            return savedLabel
        case .checking:
            return saved ? "\(savedLabel) · Checking connection…" : "Checking connection…"
        case .connected:
            return saved ? "\(savedLabel) · Connection successful" : "Connection successful"
        case .failed:
            return saved ? "\(savedLabel) · Connection failed" : "Connection failed"
        }
    }

    private var statusColor: Color {
        switch state {
        case .connected: return .green
        case .failed: return .orange
        default: return .secondary
        }
    }
}

struct CommandEditor: View {
    @ObservedObject var store: ConfigStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let originalName: String?
    let onSaved: (String) -> Void

    @State private var draft = ConfigStore.CommandDraft()
    /// Snapshot taken after load; Save stays disabled until the draft differs.
    @State private var savedDraft: ConfigStore.CommandDraft?
    @State private var models: [String] = []
    @State private var modelsError: String?
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var confirmRemoveAPIKey = false
    @State private var advancedExpanded = false
    @State private var fallbackModels: [String] = []
    @State private var fallbackModelsError: String?
    @State private var connectionState: CredentialConnectionState = .idle
    @State private var modelFetchTask: Task<Void, Never>?
    @State private var hotkeyWarning: String?
    @State private var testInput = ""
    @State private var testOutput = ""
    @State private var testError: String?
    @State private var testRunning = false
    @State private var testTask: Task<Void, Never>?

    private enum Field { case name, baseURL, apiKey, model, prompt, testInput }
    @FocusState private var focus: Field?

    private var providerNames: [String] {
        var names = Set((store.config?.providers.keys).map(Array.init) ?? [])
        names.insert(ProviderPreset.openCodeGo)
        names.insert(ProviderPreset.gemini)
        names.insert(ProviderPreset.custom)
        return names.sorted()
    }

    private var isPresetProvider: Bool {
        draft.provider == ProviderPreset.openCodeGo
            || draft.provider == ProviderPreset.gemini
            || draft.provider == ProviderPreset.custom
    }

    private func providerLabel(_ name: String) -> String {
        switch name {
        case ProviderPreset.openCodeGo: return "OpenCode Go"
        case ProviderPreset.gemini: return "Google Gemini"
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
                            VStack(alignment: .trailing, spacing: 5) {
                                KeyboardShortcuts.Recorder(for: recorderName) { shortcut in
                                    draft.hotkey = shortcut.flatMap(HotkeyParser.format) ?? ""
                                    hotkeyWarning = hotkeyConflictWarning(draft.hotkey)
                                    // Recording replaced the scratch value, which
                                    // value-unregisters any command using the old combo.
                                    store.load()
                                }
                                if let hotkeyWarning {
                                    Label(hotkeyWarning, systemImage: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.orange)
                                }
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
                                VStack(alignment: .trailing, spacing: 5) {
                                    TextField("", text: $draft.baseURL,
                                              prompt: Text("https://openrouter.ai/api/v1"))
                                        .font(.system(size: 12, design: .monospaced))
                                        .focused($focus, equals: .baseURL)
                                        .insetField(focused: focus == .baseURL)
                                    if isInsecureRemoteURL(draft.baseURL) {
                                        Label(
                                            "Plain HTTP to a remote host: the API key and your text travel unencrypted",
                                            systemImage: "lock.open")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                        if isPresetProvider {
                            RowDivider()
                            SettingRow(label: "API Key") {
                                VStack(alignment: .leading, spacing: 7) {
                                    SecureField(
                                        "", text: $draft.apiKey,
                                        prompt: Text("Enter a new API key"))
                                        .font(.system(size: 12, design: .monospaced))
                                        .focused($focus, equals: .apiKey)
                                        .onSubmit { fetchModels() }
                                        .insetField(focused: focus == .apiKey)
                                    CredentialStatus(
                                        state: connectionState,
                                        saved: hasStoredAPIKey && draft.apiKey.isEmpty,
                                        savedLabel: storedAPIKeyLabel,
                                        onRetry: fetchModels,
                                        onRemove: { confirmRemoveAPIKey = true })
                                }
                            }
                        }
                        RowDivider()
                        SettingRow(label: "Model") {
                            if models.isEmpty {
                                // Proxies without /v1/models would otherwise
                                // leave the picker empty and the form unusable.
                                TextField("", text: $draft.model, prompt: Text("model-id"))
                                    .font(.system(size: 12, design: .monospaced))
                                    .focused($focus, equals: .model)
                                    .insetField(focused: focus == .model)
                                    .frame(maxWidth: 280)
                            } else {
                                Picker("", selection: $draft.model) {
                                    if !models.contains(draft.model), !draft.model.isEmpty {
                                        Text(draft.model).tag(draft.model)
                                    }
                                    ForEach(models, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .fixedSize()
                            }
                        }
                        if let modelsError, !isPresetProvider {
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
                testSection
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
            case .model: draft.model = field.stringValue
            case .testInput: testInput = field.stringValue
            case .apiKey:
                guard draft.apiKey != field.stringValue else { return }
                draft.apiKey = field.stringValue
                modelFetchTask?.cancel()
                models = []
                modelsError = nil
                connectionState = .idle
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
        .alert("Remove saved API key?", isPresented: $confirmRemoveAPIKey) {
            Button("Remove", role: .destructive) { removeAPIKey() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The provider and its commands will be kept.")
        }
        .onAppear(perform: loadDraft)
        .onDisappear {
            modelFetchTask?.cancel()
            testTask?.cancel()
        }
    }

    /// Accordion: header toggles the fallback card, collapsed by default
    /// unless the command already has a fallback configured.
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    advancedExpanded.toggle()
                }
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
                        if let fallbackModelsError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                                Text("Couldn't load fallback models: \(fallbackModelsError)")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.orange)
                                    .lineLimit(2)
                                Spacer()
                                Button("Retry") { fetchFallbackModels() }
                                    .buttonStyle(GhostButtonStyle())
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
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

    private var hasStoredAPIKey: Bool {
        guard let apiKey = store.config?.providers[draft.provider]?.apiKey else { return false }
        return !apiKey.isEmpty
    }

    private var storedAPIKeyLabel: String {
        store.apiKeyPersistence == .keychain ? "API key saved in Keychain" : "API key saved"
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

    private func fetchFallbackModels() {
        fallbackModels = []
        fallbackModelsError = nil
        guard let provider = store.config?.providers[draft.fallbackProvider] else { return }
        let requested = draft.fallbackProvider
        Task { @MainActor in
            do {
                let fetched = try await LLMClient.listModels(
                    baseURL: provider.baseURL, apiKey: provider.apiKey)
                guard draft.fallbackProvider == requested else { return }
                fallbackModels = fetched.map {
                    ProviderPreset.normalizedModelID($0, providerName: requested)
                }
            } catch {
                guard draft.fallbackProvider == requested else { return }
                fallbackModelsError = error.localizedDescription
            }
        }
    }

    /// Canonical key order matches HotkeyParser.format: ctrl, opt, shift, cmd.
    private static let wellKnownShortcuts: [String: String] = [
        "cmd+space": "Spotlight",
        "ctrl+space": "input source switching",
        "cmd+tab": "the app switcher",
        "cmd+q": "Quit in every app",
        "cmd+w": "Close Window in every app",
        "cmd+c": "Copy in every app",
        "cmd+v": "Paste in every app",
        "shift+cmd+3": "macOS screenshots",
        "shift+cmd+4": "macOS screenshots",
        "shift+cmd+5": "macOS screenshots",
    ]

    private func hotkeyConflictWarning(_ hotkey: String) -> String? {
        guard !hotkey.isEmpty, let recorded = try? HotkeyParser.parse(hotkey) else { return nil }
        if let other = store.config?.commands.first(where: { command in
            command.name != originalName
                && command.hotkey.flatMap({ try? HotkeyParser.parse($0) }) == recorded
        }) {
            return "Already used by \"\(other.name)\" — saving will fail"
        }
        if let owner = Self.wellKnownShortcuts[hotkey] {
            return "Overrides \(owner)"
        }
        return nil
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
        hotkeyWarning = hotkeyConflictWarning(draft.hotkey)
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
        } else {
            switch draft.provider {
            case ProviderPreset.openCodeGo:
                draft.baseURL = ProviderPreset.openCodeGoBaseURL
            case ProviderPreset.gemini:
                draft.baseURL = ProviderPreset.geminiBaseURL
            default:
                draft.baseURL = ""
            }
        }
        draft.apiKey = ""
        connectionState = .idle
        // No "None" on OpenCode Go (its models all think by default).
        if draft.provider == ProviderPreset.openCodeGo, draft.reasoning.isEmpty {
            draft.reasoning = "low"
        }
    }

    /// The draft's endpoint: preset providers use their canonical URL and the
    /// draft key (falling back to the stored one); others use the saved config.
    private func resolvedEndpoint() -> (baseURL: String, apiKey: String?)? {
        if isPresetProvider {
            let baseURL: String
            switch draft.provider {
            case ProviderPreset.openCodeGo:
                baseURL = ProviderPreset.openCodeGoBaseURL
            case ProviderPreset.gemini:
                baseURL = ProviderPreset.geminiBaseURL
            default:
                baseURL = draft.baseURL
            }
            let apiKey = draft.apiKey.isEmpty
                ? store.config?.providers[draft.provider]?.apiKey
                : draft.apiKey
            return (baseURL, apiKey)
        }
        if let provider = store.config?.providers[draft.provider] {
            return (provider.baseURL, provider.apiKey)
        }
        return nil
    }

    private func fetchModels() {
        modelFetchTask?.cancel()
        models = []
        modelsError = nil
        connectionState = .idle
        guard let (baseURL, apiKey) = resolvedEndpoint() else { return }
        guard !baseURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if [ProviderPreset.openCodeGo, ProviderPreset.gemini].contains(draft.provider),
           apiKey?.isEmpty != false {
            connectionState = .idle
            return
        }
        let requestedProvider = draft.provider
        if isPresetProvider { connectionState = .checking }
        modelFetchTask = Task { @MainActor in
            do {
                let fetched = try await LLMClient.listModels(baseURL: baseURL, apiKey: apiKey)
                guard !Task.isCancelled, draft.provider == requestedProvider else { return }
                let normalized = fetched.map {
                    ProviderPreset.normalizedModelID($0, providerName: requestedProvider)
                }
                models = normalized
                if isPresetProvider { connectionState = .connected }
                if draft.model.isEmpty, let first = normalized.first {
                    draft.model = first
                }
            } catch {
                guard !Task.isCancelled, draft.provider == requestedProvider else { return }
                modelsError = error.localizedDescription
                if isPresetProvider { connectionState = .failed(error.localizedDescription) }
            }
        }
    }

    private var testSection: some View {
        section("Test", note: "Runs the draft without saving") {
            SettingsCard {
                SettingRow(label: "Sample text") {
                    TextField("", text: $testInput, prompt: Text("She go to school yesterday."))
                        .font(.system(size: 12.5))
                        .focused($focus, equals: .testInput)
                        .insetField(focused: focus == .testInput)
                }
                RowDivider()
                SettingRow(label: "Run") {
                    HStack(spacing: 8) {
                        if testRunning {
                            ProgressView().controlSize(.small)
                            Button("Stop") { testTask?.cancel() }
                                .buttonStyle(GhostButtonStyle())
                        } else {
                            Button("Run Test") { runTest() }
                                .buttonStyle(GhostButtonStyle())
                        }
                    }
                }
                if let testError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(testError)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.orange)
                            .lineLimit(3)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                if !testOutput.isEmpty {
                    ScrollView {
                        Text(testOutput)
                            .font(.system(size: 12.5))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 200)
                    .background(
                        HolsterTheme.inset,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private func runTest() {
        testTask?.cancel()
        testOutput = ""
        testError = nil
        guard let (baseURL, apiKey) = resolvedEndpoint(),
              !baseURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            testError = "Configure the provider first"
            return
        }
        let model = ProviderPreset.normalizedModelID(
            draft.model.trimmingCharacters(in: .whitespaces), providerName: draft.provider)
        guard !model.isEmpty else {
            testError = "Pick a model first"
            return
        }
        let sample = testInput.isEmpty ? "She go to school yesterday." : testInput
        let prompt = PromptTemplate.render(draft.promptText, selection: sample, clipboard: nil)
        let reasoning = CommandConfig(
            name: "test", prompt: "test", model: model,
            reasoning: draft.reasoning.isEmpty ? nil : draft.reasoning)
            .resolvedReasoning(providerName: draft.provider, model: model)
        let request = LLMRequest(
            baseURL: baseURL, apiKey: apiKey, model: model, prompt: prompt,
            reasoningEffort: reasoning)
        testRunning = true
        testTask = Task { @MainActor in
            defer { testRunning = false }
            do {
                for try await event in LLMClient.stream(request) {
                    guard !Task.isCancelled else { return }
                    if case .content(let chunk) = event { testOutput += chunk }
                }
            } catch is CancellationError {
                // Stopped by the user.
            } catch {
                guard !Task.isCancelled else { return }
                testError = error.localizedDescription
            }
        }
    }

    private func save() {
        do {
            try store.saveCommand(originalName: originalName, draft: draft)
            draft.apiKey = ""
            savedDraft = draft
            fetchModels()
            onSaved(draft.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeAPIKey() {
        do {
            modelFetchTask?.cancel()
            try store.removeAPIKey(for: draft.provider)
            draft.apiKey = ""
            models = []
            modelsError = nil
            connectionState = .idle
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
