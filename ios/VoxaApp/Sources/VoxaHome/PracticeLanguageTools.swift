import Foundation
import Observation

@MainActor
public protocol SpeechQuestionCapture: AnyObject {
    func start(localeIdentifier: String, onPartialTranscript: @escaping @MainActor (String) -> Void) async throws
    func stop() async throws -> String
    func cancel()
}

public protocol PracticeLanguageToolService: Sendable {
    func askAnything(
        question: String,
        targetLanguage: String,
        nativeLanguage: String?,
        accessToken: String
    ) async throws -> AskAnythingResult

    func translate(
        text: String,
        sourceLanguage: String?,
        targetLanguage: String,
        accessToken: String
    ) async throws -> TranslationResult

    func translateImage(
        imageBase64: String,
        mimeType: String,
        sourceLanguage: String?,
        targetLanguage: String,
        accessToken: String
    ) async throws -> ImageTranslationResult

    func vocabularyQuiz(
        targetLanguage: String,
        proficiencyBand: String,
        focus: String?,
        count: Int,
        accessToken: String
    ) async throws -> VocabularyQuizResult
}

public struct AskAnythingResult: Sendable, Equatable {
    public let answer: String
    public let examples: [PhraseExample]

    public init(answer: String, examples: [PhraseExample]) {
        self.answer = answer
        self.examples = examples
    }
}

public struct PhraseExample: Sendable, Equatable, Identifiable {
    public var id: String { "\(source)|\(target)|\(note)" }
    public let source: String
    public let target: String
    public let note: String

    public init(source: String, target: String, note: String) {
        self.source = source
        self.target = target
        self.note = note
    }
}

public struct TranslationResult: Sendable, Equatable {
    public let sourceLanguage: String
    public let targetLanguage: String
    public let translatedText: String
    public let notes: String

    public init(sourceLanguage: String, targetLanguage: String, translatedText: String, notes: String) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.translatedText = translatedText
        self.notes = notes
    }
}

public struct ImageTranslationResult: Sendable, Equatable {
    public let detectedText: String
    public let sourceLanguage: String
    public let targetLanguage: String
    public let translatedText: String
    public let notes: String

    public init(
        detectedText: String,
        sourceLanguage: String,
        targetLanguage: String,
        translatedText: String,
        notes: String
    ) {
        self.detectedText = detectedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.translatedText = translatedText
        self.notes = notes
    }
}

public struct VocabularyQuizResult: Sendable, Equatable {
    public let items: [VocabularyQuizItem]

    public init(items: [VocabularyQuizItem]) {
        self.items = items
    }
}

public struct VocabularyQuizItem: Sendable, Equatable, Identifiable {
    public var id: String { prompt }
    public let prompt: String
    public let choices: [String]
    public let correctChoiceIndex: Int
    public let explanation: String

    public init(prompt: String, choices: [String], correctChoiceIndex: Int, explanation: String) {
        self.prompt = prompt
        self.choices = choices
        self.correctChoiceIndex = correctChoiceIndex
        self.explanation = explanation
    }
}

public enum PracticeLanguageToolError: Error, Equatable {
    case appSessionRequired
    case notConfigured(String)
    case validation(String)
    case transport
    case server(code: Int, message: String)
}

public enum SpeechQuestionCaptureError: Error, Equatable {
    case unavailable
    case permissionDenied
    case recognitionFailed
    case startFailed(String)
}

public enum SpeechQuestionCaptureState: Sendable, Equatable {
    case idle
    case requestingPermission
    case recording
    case transcribing
    case failed(String)
}

public struct NotConfiguredPracticeLanguageToolService: PracticeLanguageToolService {
    private let reason: String

    public init(reason: String = "Practice language tools aren't configured for this build yet.") {
        self.reason = reason
    }

    public func askAnything(
        question: String,
        targetLanguage: String,
        nativeLanguage: String?,
        accessToken: String
    ) async throws -> AskAnythingResult {
        throw PracticeLanguageToolError.notConfigured(reason)
    }

    public func translate(
        text: String,
        sourceLanguage: String?,
        targetLanguage: String,
        accessToken: String
    ) async throws -> TranslationResult {
        throw PracticeLanguageToolError.notConfigured(reason)
    }

    public func translateImage(
        imageBase64: String,
        mimeType: String,
        sourceLanguage: String?,
        targetLanguage: String,
        accessToken: String
    ) async throws -> ImageTranslationResult {
        throw PracticeLanguageToolError.notConfigured(reason)
    }

    public func vocabularyQuiz(
        targetLanguage: String,
        proficiencyBand: String,
        focus: String?,
        count: Int,
        accessToken: String
    ) async throws -> VocabularyQuizResult {
        throw PracticeLanguageToolError.notConfigured(reason)
    }
}

@MainActor
@Observable
public final class PracticeLanguageToolViewModel {
    public private(set) var askResult: AskAnythingResult?
    public private(set) var translationResult: TranslationResult?
    public private(set) var imageTranslationResult: ImageTranslationResult?
    public private(set) var vocabularyQuiz: VocabularyQuizResult?
    public private(set) var selectedAnswers: [String: Int] = [:]
    public private(set) var spokenQuestionDraft = ""
    public private(set) var speechQuestionState: SpeechQuestionCaptureState = .idle
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let service: any PracticeLanguageToolService
    private let speechCapture: (any SpeechQuestionCapture)?
    private let accessTokenProvider: @MainActor @Sendable () -> String?

    public init(
        service: any PracticeLanguageToolService,
        speechCapture: (any SpeechQuestionCapture)? = nil,
        accessTokenProvider: @escaping @MainActor @Sendable () -> String?
    ) {
        self.service = service
        self.speechCapture = speechCapture
        self.accessTokenProvider = accessTokenProvider
    }

    public var isRecordingQuestion: Bool {
        speechQuestionState == .recording
    }

    public func askAnything(question: String, targetLanguage: String, nativeLanguage: String?) async {
        await run { [self] in
            self.askResult = try await self.service.askAnything(
                question: question,
                targetLanguage: targetLanguage,
                nativeLanguage: nativeLanguage,
                accessToken: try self.accessToken())
        }
    }

    public func startVoiceQuestionInput(localeIdentifier: String) async {
        guard let speechCapture else {
            speechQuestionState = .failed("Voice input is not available for this build.")
            return
        }

        spokenQuestionDraft = ""
        speechQuestionState = .requestingPermission
        do {
            try await speechCapture.start(localeIdentifier: localeIdentifier) { [weak self] transcript in
                self?.spokenQuestionDraft = transcript
            }
            speechQuestionState = .recording
        } catch {
            speechQuestionState = .failed(Self.speechMessage(for: error))
        }
    }

    @discardableResult
    public func stopVoiceQuestionInput() async -> String? {
        guard let speechCapture else {
            speechQuestionState = .failed("Voice input is not available for this build.")
            return nil
        }

        speechQuestionState = .transcribing
        do {
            let transcript = try await speechCapture.stop().trimmingCharacters(in: .whitespacesAndNewlines)
            spokenQuestionDraft = transcript
            speechQuestionState = .idle
            return transcript.isEmpty ? nil : transcript
        } catch {
            speechQuestionState = .failed(Self.speechMessage(for: error))
            return nil
        }
    }

    public func cancelVoiceQuestionInput() {
        speechCapture?.cancel()
        spokenQuestionDraft = ""
        speechQuestionState = .idle
    }

    public func translate(text: String, sourceLanguage: String?, targetLanguage: String) async {
        await run { [self] in
            self.translationResult = try await self.service.translate(
                text: text,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                accessToken: try self.accessToken())
        }
    }

    public func translateImage(
        imageBase64: String,
        mimeType: String,
        sourceLanguage: String?,
        targetLanguage: String
    ) async {
        await run { [self] in
            self.imageTranslationResult = try await self.service.translateImage(
                imageBase64: imageBase64,
                mimeType: mimeType,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                accessToken: try self.accessToken())
        }
    }

    public func loadVocabularyQuiz(targetLanguage: String, proficiencyBand: String, focus: String?) async {
        await run { [self] in
            self.selectedAnswers = [:]
            self.vocabularyQuiz = try await self.service.vocabularyQuiz(
                targetLanguage: targetLanguage,
                proficiencyBand: proficiencyBand,
                focus: focus,
                count: 5,
                accessToken: try self.accessToken())
        }
    }

    public func selectAnswer(_ index: Int, for item: VocabularyQuizItem) {
        selectedAnswers[item.id] = index
    }

    public func isCorrect(_ item: VocabularyQuizItem) -> Bool? {
        guard let selected = selectedAnswers[item.id] else { return nil }
        return selected == item.correctChoiceIndex
    }

    private func run(_ action: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await action()
        } catch {
            errorMessage = Self.message(for: error)
        }
        isLoading = false
    }

    private func accessToken() throws -> String {
        guard let token = accessTokenProvider(), !token.isEmpty else {
            throw PracticeLanguageToolError.appSessionRequired
        }
        return token
    }

    private static func message(for error: Error) -> String {
        switch error {
        case PracticeLanguageToolError.appSessionRequired:
            return "Please sign in again to use practice tools."
        case let PracticeLanguageToolError.notConfigured(reason):
            return reason
        case let PracticeLanguageToolError.validation(message):
            return message
        case PracticeLanguageToolError.transport:
            return "We couldn't reach voxa. Check your connection and try again."
        case let PracticeLanguageToolError.server(_, message):
            return message
        default:
            return "The practice tool could not finish. Please try again."
        }
    }

    private static func speechMessage(for error: Error) -> String {
        switch error {
        case SpeechQuestionCaptureError.unavailable:
            return "Voice input is not available on this device."
        case SpeechQuestionCaptureError.permissionDenied:
            return "Microphone and speech recognition access are required to ask by voice."
        case SpeechQuestionCaptureError.recognitionFailed:
            return "We couldn't understand that question. Please try again."
        case let SpeechQuestionCaptureError.startFailed(message):
            return message.isEmpty ? "Voice input could not start. Please try again." : message
        default:
            return "Voice input could not start. Please try again."
        }
    }
}
