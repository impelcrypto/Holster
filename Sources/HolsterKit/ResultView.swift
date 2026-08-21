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

/// Blurred backdrop for the floating panel. The panel never activates the
/// app, so without an explicit .active state the blur renders flat.
private struct PanelBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct PulsingDot: View {
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(HolsterTheme.accent)
            .frame(width: 7, height: 7)
            .opacity(dimmed ? 0.25 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { dimmed = true }
    }
}

struct ResultView: View {
    @ObservedObject var model: RunViewModel
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
        .background(PanelBackdrop().ignoresSafeArea())
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
        .animation(.easeInOut(duration: 0.15), value: model.toast)
        .tint(HolsterTheme.accentDeep)
        // SwiftUI's .textSelection is NSTextView-backed; read its selection so
        // Speak targets exactly what the user highlighted.
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { note in
            guard let tv = note.object as? NSTextView else { return }
            model.setSelectedText((tv.string as NSString).substring(with: tv.selectedRange()))
        }
    }

    private var hairline: some View {
        Rectangle().fill(HolsterTheme.hairline).frame(height: 1)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.commandName)
                .font(.system(size: 14, weight: .semibold))
            Text(model.modelName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(HolsterTheme.hairline, lineWidth: 1))
            Spacer()
            if model.state == .capturing || model.state == .streaming {
                Text(model.isReasoning && model.markdown.isEmpty ? "Reasoning…" : "Generating…")
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
        case .capturing:
            Spacer()
            Text("Capturing selection…").foregroundStyle(.secondary)
            Spacer()
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
            Spacer()
            Button("Speak") { model.onSpeak?(model.selectedText) }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.selectedText.isEmpty)
            Button("Copy All") { copy(model.fullText, closing: false) }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(model.fullText.isEmpty)
            Button {
                copy(model.smartCopyText, closing: true)
            } label: {
                HStack(spacing: 5) {
                    Text("Copy")
                    Text("⌘↩")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.45))
                }
            }
            .buttonStyle(AccentButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.state != .done)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func copy(_ text: String, closing: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if closing {
            model.onCopied?()
        } else {
            model.flashToast("Copied")
        }
    }
}
