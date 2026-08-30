import XCTest
@testable import HolsterKit

@MainActor
final class RunViewModelTests: XCTestCase {
    private func makeModel() -> RunViewModel {
        RunViewModel(command: CommandConfig(name: "Test", prompt: "t.md", model: "m"))
    }

    func testAppendCoalescesRendersUntilFlush() async throws {
        let model = makeModel()
        model.append("Hello ")
        model.append("world")
        XCTAssertEqual(model.markdown, "")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.markdown, "Hello world")
    }

    func testFinishFlushesPendingChunksImmediately() {
        let model = makeModel()
        model.append("abc")
        model.finish()
        XCTAssertEqual(model.markdown, "abc")
        XCTAssertEqual(model.state, .done)
    }

    func testSmartCopyFallsBackToFullResponseNotSelection() {
        let model = makeModel()
        model.selection = "the user's own input"
        model.append("# Heading only\n\n| a | b |\n|---|---|\n| 1 | 2 |")
        model.finish()
        XCTAssertEqual(model.smartCopyText, model.fullText)
        XCTAssertFalse(model.smartCopyText.contains("the user's own input"))
    }

    func testSmartCopyExtractsBeforeFlush() {
        let model = makeModel()
        model.append("The corrected sentence.")
        XCTAssertEqual(model.markdown, "")
        XCTAssertEqual(model.smartCopyText, "The corrected sentence.")
    }

    func testSetSelectedTextKeepsLastNonEmptySelection() {
        let model = makeModel()
        model.setSelectedText("  hello  ")
        XCTAssertEqual(model.selectedText, "hello")
        // Clicking Speak resigns the field editor, which fires an
        // empty-selection event just before the action reads the value.
        model.setSelectedText("")
        XCTAssertEqual(model.selectedText, "hello")
    }
}
