#if canImport(SwiftUI)
import XCTest
@testable import VoxaOnboarding

/// The custom-language text field in the onboarding target-language step
/// pipes free-text through `OnboardingView.capitalizingFirstLetter`. This
/// covers the value-level guard: iOS soft keyboards default-capitalise the
/// first letter of a sentence, but paste, hardware keyboards, and some
/// custom keyboards bypass that. The transform is what keeps the stored
/// language name proper-cased regardless of input path.
final class CustomLanguageCapitalizationTests: XCTestCase {
    func testUppercasesFirstLetterOfALowercaseName() {
        XCTAssertEqual(OnboardingView.capitalizingFirstLetter("russian"), "Russian")
    }

    func testLeavesInteriorCasingAlone() {
        // "Old norse" gets the first letter capitalised; the "n" in "norse"
        // is left untouched — we're not doing title-case, just leading cap.
        XCTAssertEqual(OnboardingView.capitalizingFirstLetter("old norse"), "Old norse")
    }

    func testAcceptsAnAlreadyCapitalisedName() {
        XCTAssertEqual(OnboardingView.capitalizingFirstLetter("French"), "French")
    }

    func testEmptyStringPassesThroughUnchanged() {
        XCTAssertEqual(OnboardingView.capitalizingFirstLetter(""), "")
    }

    func testSingleCharacterUppercases() {
        XCTAssertEqual(OnboardingView.capitalizingFirstLetter("f"), "F")
    }

    func testPreservesUnicodeCharacters() {
        // A pasted "ελληνικά" (Greek) should surface as "Ελληνικά".
        XCTAssertEqual(OnboardingView.capitalizingFirstLetter("ελληνικά"), "Ελληνικά")
    }
}
#endif
