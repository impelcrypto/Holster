import SwiftUI

/// Speak settings: pick the Edge TTS voice used by the Speak action.
struct SpeakSettingsView: View {
    @ObservedObject var store: ConfigStore

    @State private var voices: [EdgeVoice] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var locale = "en-US"
    @State private var voiceID = EdgeTTS.defaultVoice
    @State private var previewText = "Hi, this is a preview of the selected voice."
    @State private var speaker = Speaker()

    private var locales: [String] {
        Array(Set(voices.map(\.locale))).sorted {
            localeName($0).localizedCaseInsensitiveCompare(localeName($1)) == .orderedAscending
        }
    }

    private var localeVoices: [EdgeVoice] {
        voices.filter { $0.locale == locale }.sorted { $0.shortName < $1.shortName }
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
        .task { await loadVoices() }
    }

    private var voiceSection: some View {
        SettingsSection(title: "Voice", note: "Microsoft Edge TTS, used when you press Speak") {
            SettingsCard {
                if loading {
                    row { ProgressView().controlSize(.small); Text("Loading voices…").foregroundStyle(.secondary) }
                } else if let loadError {
                    row {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(loadError).foregroundStyle(.orange).lineLimit(2)
                        Spacer()
                        Button("Retry") { Task { await loadVoices() } }
                            .buttonStyle(GhostButtonStyle())
                    }
                } else {
                    SettingRow(label: "Language") {
                        Picker("", selection: $locale) {
                            ForEach(locales, id: \.self) { Text(localeName($0)).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: locale) { reconcileVoiceWithLocale() }
                    }
                    RowDivider()
                    SettingRow(label: "Voice") {
                        Picker("", selection: Binding(get: { voiceID }, set: { selectVoice($0) })) {
                            ForEach(localeVoices) { Text(voiceLabel($0)).tag($0.shortName) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    RowDivider()
                    SettingRow(label: "Preview") {
                        Button { play() } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                    RowDivider()
                    VStack(alignment: .leading, spacing: 0) {
                        TextEditor(text: $previewText)
                            .font(.system(size: 12.5))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 60)
                            .padding(8)
                            .background(HolsterTheme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(HolsterTheme.hairline, lineWidth: 1))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .font(.system(size: 12.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func play() {
        let text = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        speaker.speak(
            text.isEmpty ? "Hi, this is a preview of the selected voice." : text,
            config: TTSConfig(provider: "edge", voice: voiceID))
    }

    private func loadVoices() async {
        loading = true
        loadError = nil
        if let saved = store.config?.tts?.voice, !saved.isEmpty { voiceID = saved }
        do {
            let fetched = try await EdgeTTS.listVoices()
            voices = fetched
            if let match = fetched.first(where: { $0.shortName == voiceID }) {
                locale = match.locale
            } else if let first = fetched.first(where: { $0.locale == locale }) {
                voiceID = first.shortName
            }
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    /// After a language switch, keep the selected voice valid for that locale.
    private func reconcileVoiceWithLocale() {
        guard !localeVoices.contains(where: { $0.shortName == voiceID }) else { return }
        if let first = localeVoices.first { selectVoice(first.shortName) }
    }

    private func selectVoice(_ shortName: String) {
        voiceID = shortName
        // The picker only shows once config loaded, so a throw means a missing
        // config — and then there is nothing to persist to anyway.
        try? store.saveTTS(voice: shortName)
    }

    private func localeName(_ locale: String) -> String {
        Locale.current.localizedString(forIdentifier: locale) ?? locale
    }

    private func voiceLabel(_ voice: EdgeVoice) -> String {
        let last = voice.shortName.split(separator: "-").last.map(String.init) ?? voice.shortName
        let name = last.hasSuffix("Neural") ? String(last.dropLast("Neural".count)) : last
        return "\(name) · \(voice.gender)"
    }
}
