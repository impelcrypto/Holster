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

    /// A double/triple click selects without dragging, which the old
    /// drag-distance gate skipped entirely.
    func testCopyOnSelectCopiesAClickSelection() async throws {
        let model = RunViewModel(
            command: CommandConfig(name: "T", prompt: "t.md", model: "m", copyOnSelect: true))
        var copied: String?
        model.writeToPasteboard = { copied = $0 }
        model.setSelectedText("a whole paragraph")
        XCTAssertNil(copied)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(copied, "a whole paragraph")
        XCTAssertEqual(model.toast, "Copied selection")
    }

    func testCopyOnSelectOffDoesNotTouchThePasteboard() async throws {
        let model = makeModel()
        var copied: String?
        model.writeToPasteboard = { copied = $0 }
        model.setSelectedText("hello")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(copied)
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
