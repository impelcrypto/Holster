import AppKit
import SwiftUI

/// Settings landing screen: app identity and appearance. The Speak voice lives
/// on its own screen.
struct GeneralSettingsView: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                SettingsSection(title: "Appearance") {
                    SettingsCard {
                        SettingRow(label: "Theme") {
                            SegmentedPicker(
                                options: AppearancePreference.allCases.map {
                                    (label: $0.label, value: $0.rawValue)
                                },
                                selection: Binding(
                                    get: { appearance.rawValue },
                                    set: { appearance = AppearancePreference(rawValue: $0) ?? .system }))
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(HolsterTheme.windowBackground.ignoresSafeArea())
        .navigationTitle("General")
        .onChange(of: appearance) { appearance.apply() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Holster").font(.system(size: 20, weight: .semibold))
                Text("Version \(appVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
