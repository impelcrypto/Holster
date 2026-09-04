import AppKit
import SwiftUI

/// Harper-style onboarding: status banner, progress and numbered steps.
/// Step 3 is optional and never blocks the "all set" state.
struct GettingStartedView: View {
    @ObservedObject var store: ConfigStore
    @AppStorage(VisualStyle.storageKey) private var visualStyle = VisualStyle.standard
    @State private var accessibilityGranted = SelectionCapture.hasPermission
    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isReady {
                    StatusBanner(
                        kind: .success,
                        title: "You're all set",
                        message: "Holster is ready to run the commands you choose. You can revisit any section from the sidebar.")
                } else {
                    StatusBanner(
                        kind: .warning,
                        title: "Holster is not checking anything yet",
                        message: "Grant Accessibility permission so Holster can grab the selected text.")
                }

                VStack(alignment: .leading, spacing: 10) {
                    // Western style tints the overline brass via HolsterTheme.
                    Text("Getting started")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(HolsterTheme.overline)
                        .textCase(.uppercase)
                        .padding(.leading, 2)
                    Text("Let's get Holster up and running.")
                        .font(.system(size: 24, weight: .bold))
                    SetupProgressBar(done: doneCount, total: 2)
                }

                SettingsCard {
                    stepRow(
                        status: accessibilityGranted ? .done : .current(1),
                        title: "Grant Accessibility permission",
                        message: "Open system settings and grant Holster access to the Accessibility system.",
                        dimmed: false
                    ) {
                        if !accessibilityGranted {
                            Button("Recheck Permission") { accessibilityGranted = SelectionCapture.hasPermission }
                                .buttonStyle(AccentButtonStyle())
                        }
                    }
                    if !accessibilityGranted {
                        VStack(alignment: .leading, spacing: 0) {
                            RowDivider()
                            HStack(alignment: .top, spacing: 12) {
                                Spacer().frame(width: 30)
                                HStack(spacing: 12) {
                                    Text("A")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 34, height: 34)
                                        // Deep leather keeps the white glyph
                                        // readable; brass is too bright behind it.
                                        .background(
                                            LinearGradient(
                                                colors: [Color(hex: 0x6B421F), Color(hex: 0x4A2E14)],
                                                startPoint: .top, endPoint: .bottom),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Waiting for macOS")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("After granting access in System Settings, return here and recheck permission.")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Open Settings") { SelectionCapture.requestPermission() }
                                        .buttonStyle(GhostButtonStyle())
                                }
                                .padding(14)
                                .background(HolsterTheme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(HolsterTheme.hairline, lineWidth: 1))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    RowDivider()
                    stepRow(
                        status: hasCommands ? .done : accessibilityGranted ? .current(2) : .pending(2),
                        title: "Pick a command to try",
                        message: "Start with the seeded examples, then add more prompts from the sidebar when you are ready.",
                        dimmed: !hasCommands && !accessibilityGranted
                    ) {
                        Text("\(store.config?.commands.count ?? 0) commands")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    RowDivider()
                    stepRow(
                        status: .pending(3),
                        title: "Take a test drive",
                        message: "Select text in any app, press your hotkey, and watch Holster ride out.",
                        dimmed: true,
                        optional: true
                    ) {
                        EmptyView()
                    }
                }

                Text("Local-first by default. Your text stays on this Mac except for the LLM calls you trigger.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(HolsterTheme.windowBackground.ignoresSafeArea())
        .navigationTitle("Getting Started")
        .onChange(of: visualStyle) {}
        .onReceive(permissionTimer) { _ in
            accessibilityGranted = SelectionCapture.hasPermission
        }
    }

    private var hasCommands: Bool { !(store.config?.commands.isEmpty ?? true) }

    private var isReady: Bool { accessibilityGranted && hasCommands }

    private var doneCount: Int {
        (accessibilityGranted ? 1 : 0) + (hasCommands ? 1 : 0)
    }

    @ViewBuilder
    private func stepRow<Trailing: View>(
        status: StepStatusIcon.State,
        title: String,
        message: String,
        dimmed: Bool,
        optional: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            StepStatusIcon(state: status)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                    if optional {
                        Text("Optional")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                }
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .opacity(dimmed ? 0.55 : 1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
