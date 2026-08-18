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

struct ResultView: View {
    @ObservedObject var model: RunViewModel
    var onContentHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 160)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 54)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.toast)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.commandName).font(.headline)
            Text(model.modelName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.state == .capturing || model.state == .streaming {
                if model.isReasoning, model.markdown.isEmpty {
                    Text("Reasoning…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
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
        HStack(spacing: 12) {
            if case .failed = model.state {
                Button("Retry") { model.onRetry?() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            Spacer()
            Button("Speak") { model.onSpeak?(model.smartCopyText) }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.state != .done)
            Button("Copy All") { copy(model.fullText, closing: false) }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(model.fullText.isEmpty)
            Button("Copy") { copy(model.smartCopyText, closing: true) }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
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
