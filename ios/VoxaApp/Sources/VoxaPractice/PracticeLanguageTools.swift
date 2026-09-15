import Foundation

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
