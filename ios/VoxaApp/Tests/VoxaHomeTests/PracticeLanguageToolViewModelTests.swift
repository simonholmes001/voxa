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

    func testVoiceQuestionInputStoresPartialAndFinalTranscript() async {
        let speechCapture = StubSpeechQuestionCapture(finalTranscript: "How do I order coffee?")
        let model = PracticeLanguageToolViewModel(
            service: StubPracticeLanguageToolService(),
            speechCapture: speechCapture,
            accessTokenProvider: { "access-token" })

        await model.startVoiceQuestionInput(localeIdentifier: "en-US")

        XCTAssertEqual(speechCapture.startedLocaleIdentifier, "en-US")
        XCTAssertEqual(model.speechQuestionState, .recording)
        XCTAssertEqual(model.spokenQuestionDraft, "How do I")

        let transcript = await model.stopVoiceQuestionInput()

        XCTAssertEqual(transcript, "How do I order coffee?")
        XCTAssertEqual(model.spokenQuestionDraft, "How do I order coffee?")
        XCTAssertEqual(model.speechQuestionState, .idle)
    }

    func testVoiceQuestionInputUnavailableShowsMessage() async {
        let model = PracticeLanguageToolViewModel(
            service: StubPracticeLanguageToolService(),
            accessTokenProvider: { "access-token" })

        await model.startVoiceQuestionInput(localeIdentifier: "en-US")

        XCTAssertEqual(model.speechQuestionState, .failed("Voice input is not available for this build."))
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

    private final class StubSpeechQuestionCapture: SpeechQuestionCapture {
        private let finalTranscript: String
        private(set) var startedLocaleIdentifier: String?

        init(finalTranscript: String) {
            self.finalTranscript = finalTranscript
        }

        func start(
            localeIdentifier: String,
            onPartialTranscript: @escaping @MainActor (String) -> Void
        ) async throws {
            startedLocaleIdentifier = localeIdentifier
            onPartialTranscript("How do I")
        }

        func stop() async throws -> String {
            finalTranscript
        }

        func cancel() {}
    }
}
