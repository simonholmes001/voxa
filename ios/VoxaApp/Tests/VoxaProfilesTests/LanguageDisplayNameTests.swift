import XCTest
@testable import VoxaProfiles

final class LanguageDisplayNameTests: XCTestCase {

    func testTitleCasedRaisesFirstLetter() {
        XCTAssertEqual(LanguageDisplayName.titleCased("greek"), "Greek")
        XCTAssertEqual(LanguageDisplayName.titleCased("portuguese"), "Portuguese")
    }

    func testTitleCasedLeavesAlreadyTitledNamesAlone() {
        XCTAssertEqual(LanguageDisplayName.titleCased("German"), "German")
        XCTAssertEqual(LanguageDisplayName.titleCased("French"), "French")
    }

    func testTitleCasedNormalisesShoutedInput() {
        // Some learners type in caps — Home shouldn't preserve that shape.
        XCTAssertEqual(LanguageDisplayName.titleCased("GREEK"), "Greek")
    }

    func testTitleCasedTrimsWhitespace() {
        XCTAssertEqual(LanguageDisplayName.titleCased("  greek  "), "Greek")
    }

    func testTitleCasedHandlesEmptyString() {
        XCTAssertEqual(LanguageDisplayName.titleCased(""), "")
        XCTAssertEqual(LanguageDisplayName.titleCased("   "), "")
    }

    func testStringExtensionMatchesTitleCased() {
        XCTAssertEqual("greek".asLanguageDisplayName, "Greek")
    }
}
