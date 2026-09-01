import AVFoundation
import SwiftUI

/// Speak settings: pick where the Speak action gets its audio — Microsoft's
/// Edge voices or the ones installed on this Mac — and which voice.
struct SpeakSettingsView: View {
    @ObservedObject var store: ConfigStore

    private enum VoiceSource: String, Hashable { case edge, system }

    /// Apple's own instructions for downloading extra voices. The System
    /// Settings pane was renamed in macOS 15, so link instead of naming a path.
    private static let voiceHelpURL = URL(
        string: "https://support.apple.com/guide/mac-help/mchlp2290/mac")

    @State private var source = VoiceSource.edge
    @State private var voices: [EdgeVoice] = []
    @State private var systemVoices: [AVSpeechSynthesisVoice] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var locale = "en-US"
    @State private var edgeVoiceID = EdgeTTS.defaultVoice
    @State private var systemVoiceID = ""
    @State private var previewText = "Hi, this is a preview of the selected voice."
    @State private var saveError: String?
    @State private var speaker = Speaker()

    /// An OpenAI-compatible endpoint set in config.yaml wins over both sources,
    /// and the GUI has no fields for it, so it only reports what it found.
    private var hasCustomEndpoint: Bool {
        !(store.config?.tts?.baseURL ?? "").isEmpty
    }

    private var localeNames: [String] {
        let all = source == .edge ? voices.map(\.locale) : systemVoices.map(\.language)
        return Array(Set(all)).sorted {
            localeName($0).localizedCaseInsensitiveCompare(localeName($1)) == .orderedAscending
        }
    }

    private var localeVoices: [EdgeVoice] {
        voices.filter { $0.locale == locale }.sorted { $0.shortName < $1.shortName }
    }

    private var localeSystemVoices: [AVSpeechSynthesisVoice] {
        systemVoices
            .filter { $0.language == locale }
            .sorted {
                $0.quality.rawValue != $1.quality.rawValue
                    ? $0.quality.rawValue > $1.quality.rawValue
                    : $0.name < $1.name
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                voiceSection
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(HolsterTheme.windowBackground.ignoresSafeArea())
        .navigationTitle("Speak")
        .task { await load() }
    }

    private var voiceSection: some View {
        SettingsSection(title: "Voice", note: "Used when you press Speak") {
            SettingsCard {
                if hasCustomEndpoint {
                    noteRow("gearshape.fill", .secondary) {
                        Text("Speech comes from the endpoint at tts.base_url in config.yaml. Remove it to pick a voice here.")
                    }
                } else {
                    SettingRow(label: "Source") {
                        Picker("", selection: Binding(get: { source }, set: { selectSource($0) })) {
                            Text("Edge").tag(VoiceSource.edge)
                            Text("System").tag(VoiceSource.system)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    RowDivider()
                    if source == .edge { edgeRows } else { systemRows }
                    if let saveError {
                        noteRow("exclamationmark.triangle.fill", .orange) {
                            Text("Couldn't save the voice: \(saveError)")
                        }
                    }
                    RowDivider()
                    previewRows
                }
            }
        }
    }

    @ViewBuilder
    private var edgeRows: some View {
        noteRow("exclamationmark.triangle.fill", .orange) {
            Text("Edge voices are Microsoft's. Whatever you ask Holster to speak is sent to their read-aloud service. Switch to System to keep it on your Mac.")
        }
        RowDivider()
        if loading {
            row {
                ProgressView().controlSize(.small)
                Text("Loading voices…").foregroundStyle(.secondary)
            }
        } else if let loadError {
            row {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(loadError).foregroundStyle(.orange).lineLimit(2)
                Spacer()
                Button("Retry") { Task { await loadEdgeVoices() } }
                    .buttonStyle(GhostButtonStyle())
            }
        } else {
            SettingRow(label: "Language") {
                Picker("", selection: $locale) {
                    ForEach(localeNames, id: \.self) { Text(localeName($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: locale) { reconcileVoiceWithLocale() }
            }
            RowDivider()
            SettingRow(label: "Voice") {
                Picker("", selection: Binding(get: { edgeVoiceID }, set: { selectEdgeVoice($0) })) {
                    ForEach(localeVoices) { Text(edgeVoiceLabel($0)).tag($0.shortName) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var systemRows: some View {
        SettingRow(label: "Language") {
            Picker("", selection: $locale) {
                ForEach(localeNames, id: \.self) { Text(localeName($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: locale) { reconcileVoiceWithLocale() }
        }
        RowDivider()
        SettingRow(label: "Voice") {
            Picker("", selection: Binding(get: { systemVoiceID }, set: { selectSystemVoice($0) })) {
                ForEach(localeSystemVoices, id: \.identifier) {
                    Text(systemVoiceLabel($0)).tag($0.identifier)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        if !localeSystemVoices.contains(where: { $0.quality == .premium }) {
            RowDivider()
            noteRow("sparkles", .secondary) {
                HStack(spacing: 4) {
                    Text("The standard voices sound flat. A Premium one is a free download.")
                    if let url = Self.voiceHelpURL {
                        Link("How to add one", destination: url)
                            .foregroundStyle(HolsterTheme.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var previewRows: some View {
        SettingRow(label: "Preview") {
            Button { play() } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(GhostButtonStyle())
        }
        RowDivider()
        TextEditor(text: $previewText)
            .font(.system(size: 12.5))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 60)
            .padding(8)
            .background(HolsterTheme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(HolsterTheme.hairline, lineWidth: 1))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .font(.system(size: 12.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func noteRow<Content: View>(
        _ icon: String, _ tint: Color, @ViewBuilder _ content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            content().fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func play() {
        let text = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        speaker.speak(
            text.isEmpty ? "Hi, this is a preview of the selected voice." : text,
            config: source == .edge
                ? TTSConfig(provider: "edge", voice: edgeVoiceID)
                : TTSConfig(provider: "system", voice: systemVoiceID))
    }

    private func load() async {
        systemVoices = AVSpeechSynthesisVoice.speechVoices()
        let tts = store.config?.tts
        let saved = tts?.voice ?? ""
        source = tts?.provider == "edge" ? .edge : .system
        if source == .edge {
            if !saved.isEmpty { edgeVoiceID = saved }
        } else if !saved.isEmpty, systemVoices.contains(where: { $0.identifier == saved }) {
            systemVoiceID = saved
        }
        if systemVoiceID.isEmpty { systemVoiceID = defaultSystemVoiceID() }
        guard !hasCustomEndpoint else { return }
        if source == .edge {
            await loadEdgeVoices()
        } else {
            loading = false
            syncLocaleWithSystemVoice()
        }
    }

    private func loadEdgeVoices() async {
        loading = true
        loadError = nil
        do {
            let fetched = try await EdgeTTS.listVoices()
            voices = fetched
            if let match = fetched.first(where: { $0.shortName == edgeVoiceID }) {
                locale = match.locale
            } else if let first = fetched.first(where: { $0.locale == locale }) {
                edgeVoiceID = first.shortName
            }
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    private func selectSource(_ next: VoiceSource) {
        guard next != source else { return }
        source = next
        switch next {
        case .edge:
            save(provider: "edge", voice: edgeVoiceID)
            if voices.isEmpty {
                Task { await loadEdgeVoices() }
            } else if let match = voices.first(where: { $0.shortName == edgeVoiceID }) {
                locale = match.locale
            }
        case .system:
            syncLocaleWithSystemVoice()
            save(provider: "system", voice: systemVoiceID)
        }
    }

    /// After a language switch, keep the selected voice valid for that locale.
    private func reconcileVoiceWithLocale() {
        if source == .edge {
            guard !localeVoices.contains(where: { $0.shortName == edgeVoiceID }) else { return }
            if let first = localeVoices.first { selectEdgeVoice(first.shortName) }
        } else {
            guard !localeSystemVoices.contains(where: { $0.identifier == systemVoiceID }) else { return }
            if let first = localeSystemVoices.first { selectSystemVoice(first.identifier) }
        }
    }

    private func selectEdgeVoice(_ shortName: String) {
        edgeVoiceID = shortName
        save(provider: "edge", voice: shortName)
    }

    private func selectSystemVoice(_ identifier: String) {
        systemVoiceID = identifier
        save(provider: "system", voice: identifier)
    }

    private func save(provider: String, voice: String) {
        do {
            try store.saveTTS(provider: provider, voice: voice)
            saveError = nil
        } catch {
            // A silent failure looks like a saved voice; say why it isn't.
            saveError = error.localizedDescription
        }
    }

    private func defaultSystemVoiceID() -> String {
        AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())?.identifier
            ?? systemVoices.first?.identifier
            ?? ""
    }

    private func syncLocaleWithSystemVoice() {
        if let match = systemVoices.first(where: { $0.identifier == systemVoiceID }) {
            locale = match.language
        }
    }

    private func localeName(_ locale: String) -> String {
        Locale.current.localizedString(forIdentifier: locale) ?? locale
    }

    private func edgeVoiceLabel(_ voice: EdgeVoice) -> String {
        let last = voice.shortName.split(separator: "-").last.map(String.init) ?? voice.shortName
        let name = last.hasSuffix("Neural") ? String(last.dropLast("Neural".count)) : last
        return "\(name) · \(voice.gender)"
    }

    private func systemVoiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        guard voice.quality != .default, !voice.name.contains("(") else { return voice.name }
        return "\(voice.name) (\(voice.quality == .premium ? "Premium" : "Enhanced"))"
    }
}
