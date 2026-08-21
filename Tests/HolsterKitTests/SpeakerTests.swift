import XCTest
@testable import HolsterKit

final class SpeakerTests: XCTestCase {
    func testResolveVoiceNilOrEmpty() {
        XCTAssertNil(Speaker.resolveVoice(nil))
        XCTAssertNil(Speaker.resolveVoice(""))
    }

    func testResolveVoiceUnknownName() {
        XCTAssertNil(Speaker.resolveVoice("NoSuchVoice123"))
    }
}
