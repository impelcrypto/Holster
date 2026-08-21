import AppKit
import SwiftUI

/// Design tokens for both themes. The amber/copper accent is sampled from the
/// app icon's brass and leather and stays the same in either appearance.
enum HolsterTheme {
    static let accent = Color(hex: 0xFFB354)
    static let accentDeep = Color(hex: 0xC66E3D)
    static let accentGradient = LinearGradient(
        colors: [accent, accentDeep], startPoint: .top, endPoint: .bottom)

    /// Surface layering: window < card < inset (fields, editors).
    static let windowBackground = adaptive(dark: Color(hex: 0x19181B), light: Color(hex: 0xEEEDF0))
    static let card = adaptive(dark: .white.opacity(0.05), light: .white.opacity(0.7))
    static let inset = adaptive(dark: .black.opacity(0.25), light: .black.opacity(0.05))
    static let hairline = adaptive(dark: .white.opacity(0.08), light: .black.opacity(0.1))
}

/// These tokens are `static let`, so a plain `isDark ? a : b` would freeze at
/// first use. An NSColor dynamic provider re-resolves on every draw instead.
private func adaptive(dark: Color, light: Color) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
    })
}

/// App appearance, persisted in UserDefaults. `system` leaves NSApp.appearance
/// nil so macOS drives it live.
enum AppearancePreference: String, CaseIterable {
    case system, light, dark

    static let storageKey = "appearance"

    static var stored: AppearancePreference {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init) ?? .system
    }

    var label: String { rawValue.capitalized }

    // ponytail: an already-open result panel keeps the old theme until the next
    // run; force a redraw of NSApp.windows if that ever matters.
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// Filled amber pill; dark label because white on amber fails contrast.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.black.opacity(0.8))
                .padding(.horizontal, 13)
                .padding(.vertical, 5)
                .background(HolsterTheme.accentGradient, in: Capsule())
                .brightness(configuration.isPressed ? -0.1 : hovering ? 0.07 : 0)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// Quiet translucent pill for secondary actions.
struct GhostButtonStyle: ButtonStyle {
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, tint: tint)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 13)
                .padding(.vertical, 5)
                .background(
                    Color.primary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.1 : 0.06),
                    in: Capsule())
                .overlay(Capsule().strokeBorder(HolsterTheme.hairline, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
