import AppKit
import SwiftUI

/// Markdown rendered into one NSTextView. SwiftUI's `.textSelection` is
/// per-Text, so a drag could never leave the paragraph it started in.
struct MarkdownTextView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> NSTextView {
        // TextKit 1 on purpose: NSTextTable (the markdown tables) is not laid
        // out by TextKit 2.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        let view = NSTextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = NSSize.zero
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand,
        ]
        view.linkTextAttributes = linkAttributes
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        guard view.markdownSource != markdown else { return }
        let attributed = markdownAttributedString(markdown)
        view.textStorage?.setAttributedString(attributed)
        context.coordinator.storage.setAttributedString(attributed)
        view.markdownSource = markdown
    }

    /// Measures on a private layout stack: SwiftUI probes with an infinite
    /// width, and that would leave the live container unwrapped.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let sizer = context.coordinator
        if let proposed = proposal.width, proposed.isFinite, proposed > 0 {
            sizer.width = proposed
        }
        guard sizer.width > 0 else { return nil }
        sizer.container.size = CGSize(width: sizer.width, height: CGFloat.greatestFiniteMagnitude)
        sizer.layout.ensureLayout(for: sizer.container)
        return CGSize(width: sizer.width, height: ceil(sizer.layout.usedRect(for: sizer.container).height))
    }

    func makeCoordinator() -> Sizer { Sizer() }

    /// Off-screen twin of the text view, used only for height measurement.
    // ponytail: full relayout per probe; cache width -> height if long
    // outputs ever stutter.
    final class Sizer {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        var width: CGFloat = 0

        init() {
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
        }
    }
}

private extension NSTextView {
    private static var sourceKey: UInt8 = 0

    /// The markdown the view was last built from, so a re-render that changes
    /// nothing does not wipe the user's selection.
    var markdownSource: String? {
        get { objc_getAssociatedObject(self, &Self.sourceKey) as? String }
        set { objc_setAssociatedObject(self, &Self.sourceKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

// MARK: - Conversion

private let bodySize: CGFloat = 15
private let blockSpacing: CGFloat = 12

/// The runs of one markdown block (a paragraph, heading or table cell).
private struct MarkdownBlock {
    var components: [PresentationIntent.IntentType]
    var text: NSMutableAttributedString
}

func markdownAttributedString(_ markdown: String) -> NSAttributedString {
    let parsed = (try? AttributedString(
        markdown: markdown,
        options: .init(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible)))
        ?? AttributedString(markdown)

    let blocks = groupIntoBlocks(parsed)
    let out = NSMutableAttributedString()
    var tables: [Int: NSTextTable] = [:]
    var previousEndsFlush = false

    for (index, block) in blocks.enumerated() {
        let piece = NSMutableAttributedString(attributedString: block.text)
        if piece.length == 0 || piece.string.hasSuffix("\n") == false {
            piece.append(NSAttributedString(string: "\n"))
        }
        let style = paragraphStyle(for: block, tables: &tables, isLast: index == blocks.count - 1)
        // Table cells and code lines carry no trailing spacing, so the block
        // after them has to open the gap itself.
        let endsFlush = style.paragraphSpacing == 0
        if previousEndsFlush && !endsFlush { style.paragraphSpacingBefore = blockSpacing }
        previousEndsFlush = endsFlush
        piece.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: piece.length))
        if let prefix = listPrefix(for: block) {
            piece.insert(NSAttributedString(string: prefix, attributes: [
                .font: NSFont.systemFont(ofSize: bodySize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style,
            ]), at: 0)
        }
        out.append(piece)
    }
    return out
}

private func groupIntoBlocks(_ parsed: AttributedString) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    for run in parsed.runs {
        let components = run.presentationIntent?.components ?? []
        let text = NSMutableAttributedString(
            string: String(parsed[run.range].characters),
            attributes: inlineAttributes(run: run, components: components))
        if let last = blocks.last, sameBlock(last.components, components) {
            last.text.append(text)
        } else {
            blocks.append(MarkdownBlock(components: components, text: text))
        }
    }
    return blocks
}

private func sameBlock(_ a: [PresentationIntent.IntentType], _ b: [PresentationIntent.IntentType]) -> Bool {
    a.map(\.identity) == b.map(\.identity)
}

private func inlineAttributes(
    run: AttributedString.Runs.Run, components: [PresentationIntent.IntentType]
) -> [NSAttributedString.Key: Any] {
    var size = bodySize
    var weight: NSFont.Weight = .regular
    var mono = false
    var color = NSColor.labelColor

    for component in components {
        switch component.kind {
        case .header(let level):
            size = [0, 22, 19, 16.5][min(level, 3)]
            weight = .semibold
        case .codeBlock:
            mono = true
            size = bodySize - 1.5
        case .blockQuote:
            color = .secondaryLabelColor
        case .tableHeaderRow:
            weight = .semibold
        default:
            break
        }
    }

    let inline = run.inlinePresentationIntent ?? []
    if inline.contains(.stronglyEmphasized) { weight = .bold }
    if inline.contains(.code) { mono = true }

    var font: NSFont = mono
        ? .monospacedSystemFont(ofSize: size, weight: weight)
        : .systemFont(ofSize: size, weight: weight)
    if inline.contains(.emphasized) {
        font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    if inline.contains(.strikethrough) {
        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    }
    if inline.contains(.code) {
        attributes[.backgroundColor] = NSColor.labelColor.withAlphaComponent(0.08)
    }
    if let link = run.link {
        attributes[.link] = link
    }
    return attributes
}

private func paragraphStyle(
    for block: MarkdownBlock, tables: inout [Int: NSTextTable], isLast: Bool
) -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 2
    style.paragraphSpacing = isLast ? 0 : blockSpacing

    var listDepth = 0
    for component in block.components {
        switch component.kind {
        case .unorderedList, .orderedList:
            listDepth += 1
        case .codeBlock:
            style.firstLineHeadIndent = 10
            style.headIndent = 10
            style.paragraphSpacing = 0
        case .blockQuote:
            style.firstLineHeadIndent = 14
            style.headIndent = 14
        case .table(let columns):
            let table = tables[component.identity] ?? makeTable(columns: columns.count)
            tables[component.identity] = table
            style.textBlocks = [cellBlock(block: block, table: table)]
            style.paragraphSpacing = 0
        default:
            break
        }
    }
    if listDepth > 0 {
        style.firstLineHeadIndent = CGFloat(listDepth - 1) * 20
        style.headIndent = style.firstLineHeadIndent + 18
        style.paragraphSpacing = 4
    }
    return style
}

private func makeTable(columns: Int) -> NSTextTable {
    let table = NSTextTable()
    table.numberOfColumns = columns
    table.layoutAlgorithm = .automaticLayoutAlgorithm
    table.collapsesBorders = true
    table.hidesEmptyCells = false
    return table
}

private func cellBlock(block: MarkdownBlock, table: NSTextTable) -> NSTextTableBlock {
    var row = 0
    var column = 0
    var isHeader = false
    for component in block.components {
        switch component.kind {
        case .tableCell(let index): column = Int(index)
        case .tableRow(let index): row = Int(index)
        case .tableHeaderRow: isHeader = true
        default: break
        }
    }
    let cell = NSTextTableBlock(
        table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
    cell.setBorderColor(NSColor.labelColor.withAlphaComponent(0.22))
    cell.setWidth(1, type: .absoluteValueType, for: .border)
    cell.setWidth(7, type: .absoluteValueType, for: .padding)
    if isHeader || row % 2 == 1 {
        cell.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05)
    }
    return cell
}

private func listPrefix(for block: MarkdownBlock) -> String? {
    var itemNumber: Int?
    for component in block.components {
        switch component.kind {
        case .listItem(let ordinal):
            itemNumber = ordinal
        case .unorderedList:
            return "•\t"
        case .orderedList:
            return itemNumber.map { "\($0).\t" } ?? "-\t"
        default:
            break
        }
    }
    return nil
}
