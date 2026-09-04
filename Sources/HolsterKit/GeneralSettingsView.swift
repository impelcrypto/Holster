import AppKit
import SwiftUI

/// Settings landing screen: app identity, system health and appearance. The
/// Speak voice lives on its own screen.
struct GeneralSettingsView: View {
    @ObservedObject var store: ConfigStore
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system
    @AppStorage(VisualStyle.storageKey) private var visualStyle = VisualStyle.standard
    @State private var accessibilityGranted = SelectionCapture.hasPermission
    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                statusBanner
                header
                SettingsSection(title: "System Health") {
                    SettingsCard {
                        SettingRow(label: "Accessibility") {
                            HStack(spacing: 8) {
                                statusDot(accessibilityGranted ? .green : .orange)
                                Text(accessibilityGranted
                                    ? "Granted"
                                    : "Required for selection capture")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                if !accessibilityGranted {
                                    Button("Grant…") { SelectionCapture.requestPermission() }
                                        .buttonStyle(GhostButtonStyle())
                                }
                            }
                        }
                        RowDivider()
                        SettingRow(label: "Config") {
                            HStack(spacing: 8) {
                                if let error = store.lastError {
                                    statusDot(.red)
                                    Text(error)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.red)
                                        .lineLimit(3)
                                        .textSelection(.enabled)
                                } else {
                                    statusDot(.green)
                                    Text("Loaded — \(store.config?.commands.count ?? 0) commands")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }
                                Button("Reload") { store.load() }
                                    .buttonStyle(GhostButtonStyle())
                                Button("Open Folder") { NSWorkspace.shared.open(store.directory) }
                                    .buttonStyle(GhostButtonStyle())
                            }
                        }
                        if !insecureEndpoints.isEmpty {
                            RowDivider()
                            SettingRow(label: "Cleartext HTTP") {
                                Label(
                                    "\(insecureEndpoints.joined(separator: ", ")): plain HTTP to a remote host sends keys and text unencrypted",
                                    systemImage: "lock.open")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.orange)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
                SettingsSection(title: "Appearance") {
                    SettingsCard {
                        SettingRow(label: "Mode") {
                            SegmentedPicker(
                                options: AppearancePreference.allCases.map {
                                    (label: $0.label, value: $0.rawValue)
                                },
                                selection: Binding(
                                    get: { appearance.rawValue },
                                    set: { appearance = AppearancePreference(rawValue: $0) ?? .system }))
                        }
                        RowDivider()
                        SettingRow(label: "Style") {
                            SegmentedPicker(
                                options: VisualStyle.allCases.map {
                                    (label: $0.label, value: $0.rawValue)
                                },
                                selection: Binding(
                                    get: { visualStyle.rawValue },
                                    set: { visualStyle = VisualStyle(rawValue: $0) ?? .standard }))
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
        .onReceive(permissionTimer) { _ in
            accessibilityGranted = SelectionCapture.hasPermission
        }
    }

    private func statusDot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }

    /// Provider names (plus "tts") whose base_url is plain HTTP to a
    /// non-loopback host.
    private var insecureEndpoints: [String] {
        var names = (store.config?.providers ?? [:])
            .filter { isInsecureRemoteURL($0.value.baseURL) }
            .keys.sorted()
        if let tts = store.config?.tts?.baseURL, isInsecureRemoteURL(tts) {
            names.append("tts")
        }
        return names
    }

    private var statusBanner: some View {
        Group {
            if let error = store.lastError {
                StatusBanner(
                    kind: .warning,
                    title: "Config needs attention",
                    message: error)
            } else if !accessibilityGranted {
                StatusBanner(
                    kind: .warning,
                    title: "Holster is not checking anything yet",
                    message: "Grant Accessibility permission so Holster can grab the selected text.")
            } else {
                StatusBanner(
                    kind: .success,
                    title: "You're all set",
                    message: "Holster can access text and your config is loaded.")
            }
        }
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
