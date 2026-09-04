import AppKit
import MarkdownUI
import SwiftUI

/// gitHub theme minus its opaque page background: text renders straight on
/// the panel material, tables get a translucent row tint instead.
extension MarkdownUI.Theme {
    static let holster = Theme.gitHub
        .text {
            FontSize(15)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: Color.primary.opacity(0.22)))
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.clear, Color.primary.opacity(0.05)))
                .markdownMargin(top: 0, bottom: 16)
        }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PulsingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(HolsterTheme.accent)
            .frame(width: 7, height: 7)
            .opacity(reduceMotion ? 1 : (dimmed ? 0.25 : 1))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: dimmed)
            .onAppear { dimmed = true }
    }
}

struct ResultView: View {
    @ObservedObject var model: RunViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(VisualStyle.storageKey) private var visualStyle = VisualStyle.standard
    var onContentHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            content
            hairline
            footer
        }
        .frame(minWidth: 520, minHeight: 160)
        // Opaque, not a blurred material: over a light window the translucent
        // backdrop washed the text out.
        .background(HolsterTheme.windowBackground.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(HolsterTheme.hairline, lineWidth: 1))
                    .padding(.bottom, 56)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: model.toast)
        .tint(HolsterTheme.accentDeep)
        .onChange(of: visualStyle) {}
        // SwiftUI's .textSelection is NSTextView-backed; read its selection so
        // Speak targets exactly what the user highlighted.
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { note in
            // Window filter: Settings text fields post this too, and with
            // copy_on_select on they would otherwise overwrite the clipboard.
            guard let tv = note.object as? NSTextView, tv.window is ResultPanel else { return }
            model.setSelectedText((tv.string as NSString).substring(with: tv.selectedRange()))
        }
    }

    private var hairline: some View {
        Rectangle().fill(HolsterTheme.hairline).frame(height: 1)
    }

    private var statusLabel: String {
        if model.isSelecting { return "Selecting…" }
        return model.isReasoning && model.markdown.isEmpty ? "Reasoning…" : "Generating…"
    }

    private var header: some View {
        HStack(spacing: 8) {
            if HolsterTheme.isWestern {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(HolsterTheme.accentDeep)
            }
            Text(model.commandName)
                .font(.system(size: 14, weight: .semibold))
            Text(model.modelName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: HolsterTheme.badgeRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: HolsterTheme.badgeRadius, style: .continuous)
                        .strokeBorder(HolsterTheme.isWestern ? HolsterTheme.accentDeep.opacity(0.5) : HolsterTheme.hairline, lineWidth: 1))
            Spacer()
            if model.state == .streaming || model.isSelecting {
                Text(statusLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                PulsingDot()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .failed(let message) where model.fullText.isEmpty:
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text(message)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 24)
            Spacer()
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Markdown(model.markdown)
                        .markdownTheme(.holster)
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if case .failed(let message) = model.state {
                        Text(message)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.bottom, 12)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                })
            }
            .onPreferenceChange(ContentHeightKey.self) { height in
                Task { @MainActor in onContentHeight(height) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if case .failed = model.state {
                Button {
                    model.onRetry?()
                } label: {
                    HStack(spacing: 5) {
                        Text("Retry")
                        Text("⌘R")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut("r", modifiers: .command)
            }
            if model.state == .streaming {
                Button {
                    model.onStop?()
                } label: {
                    HStack(spacing: 5) {
                        Text("Stop")
                        Text("⌘.")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut(".", modifiers: .command)
            }
            Spacer()
            // Nothing highlighted = speak the whole response.
            Button("Speak") {
                model.onSpeak?(model.selectedText.isEmpty ? model.fullText : model.selectedText)
            }
            .buttonStyle(GhostButtonStyle())
            .keyboardShortcut("s", modifiers: .command)
            .disabled(model.selectedText.isEmpty && model.fullText.isEmpty)
            // Stays enabled during Selecting… as the immediate escape hatch.
            Button("Copy All") { model.copyAll() }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(model.fullText.isEmpty)
            Button {
                model.performSmartCopy()
            } label: {
                HStack(spacing: 5) {
                    Text(model.isSelecting ? "Selecting…" : "Copy")
                    Text("⌘↩")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.45))
                }
            }
            .buttonStyle(AccentButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.state != .done || model.isSelecting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
