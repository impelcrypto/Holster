import AppKit
import XCTest
@testable import HolsterKit

final class MarkdownTextViewTests: XCTestCase {
    func testTableCellsCarryTextTableBlocks() {
        let attributed = markdownAttributedString("""
        Intro paragraph.

        | A | B |
        |---|---|
        | 1 | 2 |
        """)

        var tables: Set<ObjectIdentifier> = []
        attributed.enumerateAttribute(
            .paragraphStyle, in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            for block in (value as? NSParagraphStyle)?.textBlocks ?? [] {
                guard let cell = block as? NSTextTableBlock else { continue }
                tables.insert(ObjectIdentifier(cell.table))
            }
        }
        XCTAssertEqual(tables.count, 1, "all cells must share one NSTextTable")
        // The whole document is one string, so a drag can span paragraph and table.
        XCTAssertTrue(attributed.string.contains("Intro paragraph."))
        XCTAssertTrue(attributed.string.contains("1"))
    }
}
