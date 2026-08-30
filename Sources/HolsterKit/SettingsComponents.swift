import SwiftUI

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
