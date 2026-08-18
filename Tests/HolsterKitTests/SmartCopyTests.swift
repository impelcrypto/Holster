import XCTest
@testable import HolsterKit

final class SmartCopyTests: XCTestCase {
    func testExtractsCorrectedSentenceAndStripsItalics() {
        let markdown = """
        It *seems* a lot of people *are* getting sick.

        | Incorrect Part | Correct Version | Explanation |
        | --- | --- | --- |
        | seem | seems | Singular subject. |
        """
        XCTAssertEqual(
            SmartCopy.extract(from: markdown),
            "It seems a lot of people are getting sick.")
    }

    func testNoCorrectionsWithRephraseReturnsRephrase() {
        let markdown = """
        No grammar corrections needed.

        Natural Rephrase:

        Get well soon! It seems *a cold is going around* in Singapore.

        | Original Part | Natural Version | Why |
        | --- | --- | --- |
        | a lot of people | a cold is going around | More idiomatic. |
        """
        XCTAssertEqual(
            SmartCopy.extract(from: markdown),
            "Get well soon! It seems a cold is going around in Singapore.")
    }

    func testNoCorrectionsWithoutRephraseReturnsNil() {
        XCTAssertNil(SmartCopy.extract(from: "No grammar corrections needed."))
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(SmartCopy.extract(from: ""))
        XCTAssertNil(SmartCopy.extract(from: "\n\n"))
    }

    func testKeepsUnderscoresAndCodeSpans() {
        let markdown = "Renamed `market_type` to *marketType_v2* in the PR."
        XCTAssertEqual(
            SmartCopy.extract(from: markdown),
            "Renamed `market_type` to marketType_v2 in the PR.")
    }

    func testAsteriskInsideCodeSpanSurvives() {
        XCTAssertEqual(
            SmartCopy.stripEmphasis("Run `rm *.log` *now*."),
            "Run `rm *.log` now.")
    }

    func testCorrectedSentenceFollowedByRephraseReturnsCorrected() {
        let markdown = """
        Let's say hello to J Garcia-san before he moves to *the* US.

        | Incorrect Part | Correct Version | Explanation |
        | --- | --- | --- |
        | to US | to the US | Definite article. |

        Natural Rephrase:

        Let's say *goodbye* to J Garcia-san before he moves to the US.
        """
        XCTAssertEqual(
            SmartCopy.extract(from: markdown),
            "Let's say hello to J Garcia-san before he moves to the US.")
    }
}
