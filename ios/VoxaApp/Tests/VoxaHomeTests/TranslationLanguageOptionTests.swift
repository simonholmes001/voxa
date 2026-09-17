import XCTest
@testable import VoxaHome

final class TranslationLanguageOptionTests: XCTestCase {
    func testRegionalEnglishLocaleDisplaysAsEnglish() {
        let selection = TranslationLanguageOption.option(for: "en-US", allowsAutomatic: true)

        XCTAssertEqual(selection.option, .language("English"))
        XCTAssertEqual(selection.customLanguage, "")
    }

    func testRegionalLocaleWithUnderscoreDisplaysBaseLanguage() {
        let selection = TranslationLanguageOption.option(for: "de_DE", allowsAutomatic: false)

        XCTAssertEqual(selection.option, .language("German"))
        XCTAssertEqual(selection.customLanguage, "")
    }

    func testSwapExchangesConcreteSourceAndTarget() {
        let result = TranslationLanguageOption.swapped(
            source: (.language("English"), ""),
            target: (.language("German"), ""),
            automaticTargetFallback: (.language("French"), ""))

        XCTAssertEqual(result.source.option, .language("German"))
        XCTAssertEqual(result.target.option, .language("English"))
    }

    func testSwapUsesConcreteFallbackWhenSourceIsAutomatic() {
        let result = TranslationLanguageOption.swapped(
            source: (.automatic, ""),
            target: (.language("German"), ""),
            automaticTargetFallback: (.language("English"), ""))

        XCTAssertEqual(result.source.option, .language("German"))
        XCTAssertEqual(result.target.option, .language("English"))
    }
}
