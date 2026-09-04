import SwiftUI

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                HolsterTheme.card,
                in: RoundedRectangle(cornerRadius: HolsterTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HolsterTheme.cardRadius, style: .continuous)
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
// Western style tints the overline brass.
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
                    .foregroundStyle(HolsterTheme.overline)
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

/// Harper-style status banner: tinted wash with an icon, bold title,
/// secondary description and optional trailing action.
struct StatusBanner<Trailing: View>: View {
    enum Kind {
        case warning
        case success

        var background: Color {
            switch self {
            case .warning: HolsterTheme.bannerWarningBackground
            case .success: HolsterTheme.bannerSuccessBackground
            }
        }

        var iconName: String {
            switch self {
            case .warning: "exclamationmark"
            case .success: "checkmark"
            }
        }

        // Tinted outline so the banner reads as a card even where the wash
        // is close to the window background (e.g. peach on parchment).
        var border: Color {
            switch self {
            case .warning: HolsterTheme.bannerWarningBorder
            case .success: HolsterTheme.bannerSuccessBorder
            }
        }

        var iconBackground: LinearGradient {            switch self {
            case .warning:
                LinearGradient(
                    colors: [Color(hex: 0xC66E3D), Color(hex: 0x8C5A2B)],
                    startPoint: .top, endPoint: .bottom)
            case .success:
                LinearGradient(
                    colors: [Color(hex: 0x4CAF7D), Color(hex: 0x2E7D52)],
                    startPoint: .top, endPoint: .bottom)
            }
        }
    }

    let kind: Kind
    let title: String
    let message: String
    @ViewBuilder var trailing: Trailing

    init(kind: Kind, title: String, message: String, @ViewBuilder trailing: () -> Trailing) {
        self.kind = kind
        self.title = title
        self.message = message
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: kind.iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(kind.iconBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(16)
        .background(kind.background, in: RoundedRectangle(cornerRadius: HolsterTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HolsterTheme.cardRadius, style: .continuous)
                .strokeBorder(kind.border, lineWidth: 1))
    }
}

extension StatusBanner where Trailing == EmptyView {
    init(kind: Kind, title: String, message: String) {
        self.init(kind: kind, title: title, message: message) { EmptyView() }
    }
}

/// Numbered / check step indicator for the Getting Started card.
struct StepStatusIcon: View {
    enum State {
        case done
        case current(Int)
        case pending(Int)
    }

    let state: State

    var body: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0x4CAF7D), Color(hex: 0x2E7D52)],
                        startPoint: .top, endPoint: .bottom),
                    in: Circle())
        case .current(let n), .pending(let n):
            Text("\(n)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.05), in: Circle())
                .overlay(Circle().strokeBorder(HolsterTheme.hairline, lineWidth: 1))
        }
    }
}

/// Thin setup progress bar with "x of y" label.
struct SetupProgressBar: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(HolsterTheme.accentGradient)
                            .frame(width: proxy.size.width * fraction)
                    }
            }
            .frame(height: 6)
            Text("\(done) of \(total)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, max(0, CGFloat(done) / CGFloat(total)))
    }
}
