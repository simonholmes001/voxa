import Foundation
import VoxaHome

public struct VoxaBackendPracticeLanguageToolService: PracticeLanguageToolService {
    private let baseURL: URL
    private let session: URLSession
    private let correlationIDProvider: @Sendable () -> String

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        correlationIDProvider: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.correlationIDProvider = correlationIDProvider
    }

    public func askAnything(
        question: String,
        targetLanguage: String,
        nativeLanguage: String?,
        accessToken: String
    ) async throws -> AskAnythingResult {
        let dto = AskAnythingRequestDTO(
            targetLanguage: targetLanguage,
            nativeLanguage: nativeLanguage,
            question: question)
        let response: AskAnythingResponseDTO = try await post("api/language-tools/ask", dto, accessToken: accessToken)
        return response.toModel()
    }

    public func translate(
        text: String,
        sourceLanguage: String?,
        targetLanguage: String,
        accessToken: String
    ) async throws -> TranslationResult {
        let dto = TranslationRequestDTO(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            text: text)
        let response: TranslationResponseDTO = try await post("api/language-tools/translate", dto, accessToken: accessToken)
        return response.toModel()
    }

    public func translateImage(
        imageBase64: String,
        mimeType: String,
        sourceLanguage: String?,
        targetLanguage: String,
        accessToken: String
    ) async throws -> ImageTranslationResult {
        let dto = ImageTranslationRequestDTO(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            imageBase64: imageBase64,
            mimeType: mimeType)
        let response: ImageTranslationResponseDTO = try await post(
            "api/language-tools/translate-image",
            dto,
            accessToken: accessToken)
        return response.toModel()
    }

    public func vocabularyQuiz(
        targetLanguage: String,
        proficiencyBand: String,
        focus: String?,
        count: Int,
        accessToken: String
    ) async throws -> VocabularyQuizResult {
        let dto = VocabularyQuizRequestDTO(
            targetLanguage: targetLanguage,
            proficiencyBand: proficiencyBand,
            focus: focus,
            count: count)
        let response: VocabularyQuizResponseDTO = try await post(
            "api/practice/vocabulary-quiz",
            dto,
            accessToken: accessToken)
        return response.toModel()
    }

    private func post<TRequest: Encodable, TResponse: Decodable>(
        _ path: String,
        _ body: TRequest,
        accessToken: String
    ) async throws -> TResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(correlationIDProvider(), forHTTPHeaderField: "X-Correlation-Id")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PracticeLanguageToolError.transport
        }

        guard let http = response as? HTTPURLResponse else {
            throw PracticeLanguageToolError.transport
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }

        do {
            return try JSONDecoder().decode(TResponse.self, from: data)
        } catch {
            throw PracticeLanguageToolError.transport
        }
    }

    private static func mapError(status: Int, data: Data) -> PracticeLanguageToolError {
        let payload = try? JSONDecoder().decode(ApiErrorDTO.self, from: data)
        switch (status, payload?.code) {
        case (401, _):
            return .appSessionRequired
        case (400, _):
            return .validation(payload?.message ?? "The request was invalid.")
        default:
            return .server(code: status, message: payload?.message ?? "The server returned an error.")
        }
    }
}
