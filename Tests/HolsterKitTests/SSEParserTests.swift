import XCTest
@testable import HolsterKit

final class SSEParserTests: XCTestCase {
    func testParsesContentDelta() {
        let line = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
        XCTAssertEqual(SSEParser.parseLine(line), .delta("Hello"))
    }

    func testParsesDataWithoutSpace() {
        let line = #"data:{"choices":[{"delta":{"content":"x"}}]}"#
        XCTAssertEqual(SSEParser.parseLine(line), .delta("x"))
    }

    func testDone() {
        XCTAssertEqual(SSEParser.parseLine("data: [DONE]"), .done)
        XCTAssertEqual(SSEParser.parseLine("data:[DONE]"), .done)
    }

    func testIgnoresRoleOnlyChunk() {
        let line = #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#
        XCTAssertNil(SSEParser.parseLine(line))
    }

    func testIgnoresCommentsBlanksAndGarbage() {
        XCTAssertNil(SSEParser.parseLine(""))
        XCTAssertNil(SSEParser.parseLine(": keep-alive ping"))
        XCTAssertNil(SSEParser.parseLine("event: message"))
        XCTAssertNil(SSEParser.parseLine("data: {broken json"))
        XCTAssertNil(SSEParser.parseLine("total garbage line"))
    }

    func testSurfacesMidStreamError() {
        let line = #"data: {"error":{"message":"rate limited"}}"#
        XCTAssertEqual(SSEParser.parseLine(line), .error("rate limited"))
    }

    func testIgnoresEmptyContentDelta() {
        let line = #"data: {"choices":[{"delta":{"content":""}}]}"#
        XCTAssertNil(SSEParser.parseLine(line))
    }

    func testHandlesMultibyteContent() {
        let line = #"data: {"choices":[{"delta":{"content":"日本語🐎"}}]}"#
        XCTAssertEqual(SSEParser.parseLine(line), .delta("日本語🐎"))
    }
}
