import XCTest
@testable import VoxaHome

@MainActor
final class PracticeLanguageToolViewModelTests: XCTestCase {
    func testVocabularyQuizStoresQuizAndScoresSelectedAnswer() async throws {
        let model = PracticeLanguageToolViewModel(
            service: StubPracticeLanguageToolService(),
            accessTokenProvider: { "access-token" })

        await model.loadVocabularyQuiz(targetLanguage: "French", proficiencyBand: "A1-A2", focus: "travel")

        let item = try XCTUnwrap(model.vocabularyQuiz?.items.first)
        XCTAssertEqual(item.prompt, "Choose bread.")
        model.selectAnswer(0, for: item)
        XCTAssertEqual(model.isCorrect(item), true)
    }

    func testMissingTokenSurfacesSignInMessage() async {
        let model = PracticeLanguageToolViewModel(
            service: StubPracticeLanguageToolService(),
            accessTokenProvider: { nil })

        await model.askAnything(question: "How do I say hi?", targetLanguage: "French", nativeLanguage: nil)

        XCTAssertEqual(model.errorMessage, "Please sign in again to use practice tools.")
    }

    private struct StubPracticeLanguageToolService: PracticeLanguageToolService {
        func askAnything(
            question: String,
            targetLanguage: String,
            nativeLanguage: String?,
            accessToken: String
        ) async throws -> AskAnythingResult {
            AskAnythingResult(answer: "Bonjour", examples: [])
        }

        func translate(
            text: String,
            sourceLanguage: String?,
            targetLanguage: String,
            accessToken: String
        ) async throws -> TranslationResult {
            TranslationResult(sourceLanguage: "English", targetLanguage: targetLanguage, translatedText: "Bonjour", notes: "")
        }

        func translateImage(
            imageBase64: String,
            mimeType: String,
            sourceLanguage: String?,
            targetLanguage: String,
            accessToken: String
        ) async throws -> ImageTranslationResult {
            ImageTranslationResult(
                detectedText: "Bonjour",
                sourceLanguage: "French",
                targetLanguage: targetLanguage,
                translatedText: "Hello",
                notes: "")
        }

        func vocabularyQuiz(
            targetLanguage: String,
            proficiencyBand: String,
            focus: String?,
            count: Int,
            accessToken: String
        ) async throws -> VocabularyQuizResult {
            VocabularyQuizResult(items: [
                VocabularyQuizItem(
                    prompt: "Choose bread.",
                    choices: ["pain", "eau"],
                    correctChoiceIndex: 0,
                    explanation: "Pain means bread."),
            ])
        }
    }
}
