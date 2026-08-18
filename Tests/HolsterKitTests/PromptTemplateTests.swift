import XCTest
@testable import HolsterKit

final class PromptTemplateTests: XCTestCase {
    func testReplacesSelection() {
        let result = PromptTemplate.render("Check this:\n{selection}", selection: "It seem wrong.")
        XCTAssertEqual(result, "Check this:\nIt seem wrong.")
    }

    func testReplacesClipboardWhenProvided() {
        let result = PromptTemplate.render("{selection} / {clipboard}", selection: "a", clipboard: "b")
        XCTAssertEqual(result, "a / b")
    }

    func testLeavesClipboardPlaceholderWhenAbsent() {
        let result = PromptTemplate.render("{selection} / {clipboard}", selection: "a")
        XCTAssertEqual(result, "a / {clipboard}")
    }

    func testMultipleOccurrences() {
        let result = PromptTemplate.render("{selection}{selection}", selection: "x")
        XCTAssertEqual(result, "xx")
    }
}
