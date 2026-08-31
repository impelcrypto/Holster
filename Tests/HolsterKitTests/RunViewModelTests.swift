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

    /// Drives a model to .done with `text` and captures what it copies.
    private func makeDoneModel(_ text: String) -> (RunViewModel, () -> String?) {
        let model = makeModel()
        model.append(text)
        model.finish()
        // Boxed so the caller reads the value after the copy, not at capture.
        final class Box: @unchecked Sendable { var value: String? }
        let box = Box()
        model.writeToPasteboard = { box.value = $0 }
        return (model, { box.value })
    }

    func testSmartCopyCopiesWhatTheSelectorPicked() async throws {
        let (model, copied) = makeDoneModel("Preamble:\nThe answer.")
        model.onSmartCopy = { _ in "The answer." }
        var closed = false
        model.onCopied = { closed = true }
        model.performSmartCopy()
        XCTAssertTrue(model.isSelecting)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(copied(), "The answer.")
        XCTAssertFalse(model.isSelecting)
        XCTAssertTrue(closed)
    }

    func testSelectorFailureFallsBackToTheFullResponseNotTheSelection() async throws {
        let (model, copied) = makeDoneModel("# Heading only\n\n| a | b |")
        model.selection = "the user's own input"
        model.onSmartCopy = { _ in nil }
        model.performSmartCopy()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(copied(), model.fullText)
        XCTAssertFalse(copied()?.contains("the user's own input") ?? true)
    }

    func testCancellingSmartCopyPreventsTheLaterClipboardWrite() async throws {
        let (model, copied) = makeDoneModel("full response")
        model.onSmartCopy = { _ in
            try? await Task.sleep(for: .milliseconds(200))
            return "picked"
        }
        var closed = false
        model.onCopied = { closed = true }
        model.performSmartCopy()
        model.cancelSmartCopy()
        XCTAssertFalse(model.isSelecting)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(copied())
        XCTAssertFalse(closed)
    }

    func testRepeatedSmartCopyDoesNotStartConcurrentRequests() async throws {
        let (model, _) = makeDoneModel("full response")
        final class Counter: @unchecked Sendable { var value = 0 }
        let calls = Counter()
        model.onSmartCopy = { _ in
            calls.value += 1
            try? await Task.sleep(for: .milliseconds(150))
            return "picked"
        }
        model.performSmartCopy()
        model.performSmartCopy()
        model.performSmartCopy()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(calls.value, 1)
    }

    func testCopyAllCopiesTheFullResponseWithoutCallingTheSelector() async throws {
        let (model, copied) = makeDoneModel("Preamble:\nThe answer.")
        var selectorCalled = false
        model.onSmartCopy = { _ in
            selectorCalled = true
            return "The answer."
        }
        var closed = false
        model.onCopied = { closed = true }
        model.copyAll()
        XCTAssertEqual(copied(), "Preamble:\nThe answer.")
        XCTAssertEqual(model.toast, "Copied")
        XCTAssertFalse(closed)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(selectorCalled)
    }

    /// ⇧⌘↩ during Selecting… must win: the window stays open, so a selector
    /// landing afterwards would silently replace what the user just took.
    func testCopyAllDuringSelectionCancelsTheSelector() async throws {
        let (model, copied) = makeDoneModel("full response")
        model.onSmartCopy = { _ in
            try? await Task.sleep(for: .milliseconds(200))
            return "picked"
        }
        model.performSmartCopy()
        model.copyAll()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(copied(), "full response")
        XCTAssertFalse(model.isSelecting)
    }

    func testSmartCopyIsIgnoredBeforeTheResponseFinishes() {
        let model = makeModel()
        model.append("partial")
        model.beginStreaming()
        var called = false
        model.onSmartCopy = { _ in
            called = true
            return nil
        }
        model.performSmartCopy()
        XCTAssertFalse(model.isSelecting)
        XCTAssertFalse(called)
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
