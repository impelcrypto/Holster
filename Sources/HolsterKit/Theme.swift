import AppKit
import SwiftUI

/// Design tokens for both themes. The amber/copper accent is sampled from the
/// app icon's brass and leather and stays the same in either appearance.
/// When the Western style is active the palette shifts to brass, saddle
/// leather and parchment.
enum HolsterTheme {
    /// When true the Western palette is used. Read live from UserDefaults so
    /// `@AppStorage(VisualStyle.storageKey)` re-renders pick it up.
    static var isWestern: Bool { VisualStyle.stored == .western }

    static var accent: Color {
        isWestern ? Color(hex: 0xD9A441) : Color(hex: 0xFFB354)
    }
    static var accentDeep: Color {
        // Must stay bright enough for the near-black button label: the old
        // saddle brown only reached 2.2:1.
        isWestern ? Color(hex: 0xC07F36) : Color(hex: 0xC66E3D)
    }
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentDeep], startPoint: .top, endPoint: .bottom)
    }

    /// Surface layering: window < card < inset (fields, editors).
    static var windowBackground: Color {
        if isWestern {
            return adaptive(dark: Color(hex: 0x221A12), light: Color(hex: 0xF7F0E1))
        }
        return adaptive(dark: Color(hex: 0x19181B), light: Color(hex: 0xEEEDF0))
    }
    static var card: Color {
        if isWestern {
            return adaptive(dark: .white.opacity(0.06), light: .white.opacity(0.7))
        }
        return adaptive(dark: .white.opacity(0.05), light: .white.opacity(0.7))
    }
    static var inset: Color {
        adaptive(dark: .black.opacity(0.25), light: .black.opacity(0.05))
    }
    static var hairline: Color {
        adaptive(dark: .white.opacity(0.08), light: .black.opacity(0.1))
    }

    /// Wash alone is too close to parchment in Western, so each kind also
    /// carries a tinted border to keep the banner reading as a card.
    static var bannerWarningBackground: Color {
        adaptive(dark: Color(hex: 0x5A3620).opacity(0.7), light: Color(hex: 0xF5DFC2))
    }
    static var bannerSuccessBackground: Color {
        adaptive(dark: Color(hex: 0x24452F).opacity(0.7), light: Color(hex: 0xE2F2E6))
    }
    static var bannerWarningBorder: Color {
        adaptive(
            dark: Color(hex: 0xD9A441).opacity(0.45),
            light: Color(hex: 0xB4712F).opacity(0.5))
    }
    static var bannerSuccessBorder: Color {
        adaptive(
            dark: Color(hex: 0x4CAF7D).opacity(0.45),
            light: Color(hex: 0x2E7D52).opacity(0.4))
    }

    /// Card corner radius: slightly larger in Western for a wanted-poster feel.
    static var cardRadius: CGFloat { isWestern ? 14 : 12 }

    /// Small badge (e.g. model tag): capsule normally, squared tag in Western.
    static var badgeRadius: CGFloat { isWestern ? 6 : 20 }

    /// Section overline color: brass-tinted in Western, secondary otherwise.
    static var overline: Color {
        isWestern ? Color(hex: 0x7A4E22).opacity(0.95) : .secondary
    }
}

/// A plain `isDark ? a : b` would bake in the appearance current when the view
/// body last ran. An NSColor dynamic provider re-resolves on every draw instead.
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

/// Visual style, persisted separately from light/dark appearance so it can
/// be toggled independently.
enum VisualStyle: String, CaseIterable {
    case standard, western

    static let storageKey = "visualStyle"

    static var stored: VisualStyle {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init) ?? .standard
    }

    var label: String { rawValue.capitalized }
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
