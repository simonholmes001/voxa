import Foundation
import Observation
import VoxaPractice

@MainActor
public protocol SpeechQuestionCapture: AnyObject {
    func start(localeIdentifier: String, onPartialTranscript: @escaping @MainActor (String) -> Void) async throws
    func stop() async throws -> String
    func cancel()
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
