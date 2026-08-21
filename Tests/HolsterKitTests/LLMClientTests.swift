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
