import Foundation
import VoxaPractice

struct AskAnythingRequestDTO: Encodable {
    let targetLanguage: String
    let nativeLanguage: String?
    let question: String
}

struct PhraseExampleDTO: Decodable {
    let source: String
    let target: String
    let note: String

    func toModel() -> PhraseExample {
        PhraseExample(source: source, target: target, note: note)
    }
}

struct AskAnythingResponseDTO: Decodable {
    let answer: String
    let examples: [PhraseExampleDTO]

    func toModel() -> AskAnythingResult {
        AskAnythingResult(answer: answer, examples: examples.map { $0.toModel() })
    }
}

struct TranslationRequestDTO: Encodable {
    let sourceLanguage: String?
    let targetLanguage: String
    let text: String
}

struct TranslationResponseDTO: Decodable {
    let sourceLanguage: String
    let targetLanguage: String
    let translatedText: String
    let notes: String

    func toModel() -> TranslationResult {
        TranslationResult(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            translatedText: translatedText,
            notes: notes)
    }
}

struct ImageTranslationRequestDTO: Encodable {
    let sourceLanguage: String?
    let targetLanguage: String
    let imageBase64: String
    let mimeType: String
}

struct ImageTranslationResponseDTO: Decodable {
    let detectedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let translatedText: String
    let notes: String

    func toModel() -> ImageTranslationResult {
        ImageTranslationResult(
            detectedText: detectedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            translatedText: translatedText,
            notes: notes)
    }
}

struct VocabularyQuizRequestDTO: Encodable {
    let targetLanguage: String
    let proficiencyBand: String
    let focus: String?
    let count: Int
}

struct VocabularyQuizResponseDTO: Decodable {
    let items: [VocabularyQuizItemDTO]

    func toModel() -> VocabularyQuizResult {
        VocabularyQuizResult(items: items.map { $0.toModel() })
    }
}

struct VocabularyQuizItemDTO: Decodable {
    let prompt: String
    let choices: [String]
    let correctChoiceIndex: Int
    let explanation: String

    func toModel() -> VocabularyQuizItem {
        VocabularyQuizItem(
            prompt: prompt,
            choices: choices,
            correctChoiceIndex: correctChoiceIndex,
            explanation: explanation)
    }
}
