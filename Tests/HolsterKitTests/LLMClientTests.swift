import XCTest
@testable import HolsterKit

final class LLMClientTests: XCTestCase {
    /// A request that fails synchronously, before any content, without network.
    private let broken = LLMRequest(baseURL: "not a url", model: "m", prompt: "p")

    func testFallbackEventEmittedWhenPrimaryFailsBeforeContent() async {
        var events: [LLMEvent] = []
        var thrown: Error?
        do {
            for try await event in LLMClient.streamWithFallback(broken, fallback: broken) {
                events.append(event)
            }
        } catch {
            thrown = error
        }
        // Primary bad URL triggers the fallback, which then fails too.
        XCTAssertEqual(events, [.fallback])
        XCTAssertNotNil(thrown)
    }

    /// Existing endpoints must keep seeing the exact body they saw before, so
    /// the system message appears only when one was asked for.
    func testSystemMessageIsOmittedUnlessSet() throws {
        func messages(_ request: LLMRequest) throws -> [[String: String]] {
            let body = try XCTUnwrap(LLMClient.makeChatRequest(request).httpBody)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any])
            return try XCTUnwrap(json["messages"] as? [[String: String]])
        }
        let base = LLMRequest(baseURL: "https://example.com/v1", model: "m", prompt: "hello")
        XCTAssertEqual(try messages(base), [["role": "user", "content": "hello"]])

        var withSystem = base
        withSystem.system = "you select line ranges"
        XCTAssertEqual(try messages(withSystem), [
            ["role": "system", "content": "you select line ranges"],
            ["role": "user", "content": "hello"],
        ])
    }

    func testTimeoutIsCarriedOntoTheURLRequest() throws {
        let request = LLMRequest(
            baseURL: "https://example.com/v1", model: "m", prompt: "p", timeout: 10)
        XCTAssertEqual(try LLMClient.makeChatRequest(request).timeoutInterval, 10)
        let long = LLMRequest(baseURL: "https://example.com/v1", model: "m", prompt: "p")
        XCTAssertEqual(try LLMClient.makeChatRequest(long).timeoutInterval, 300)
    }

    func testNoFallbackConfiguredPropagatesError() async {
        var events: [LLMEvent] = []
        var thrown: Error?
        do {
            for try await event in LLMClient.streamWithFallback(broken, fallback: nil) {
                events.append(event)
            }
        } catch {
            thrown = error
        }
        XCTAssertEqual(events, [])
        XCTAssertNotNil(thrown)
    }
}
