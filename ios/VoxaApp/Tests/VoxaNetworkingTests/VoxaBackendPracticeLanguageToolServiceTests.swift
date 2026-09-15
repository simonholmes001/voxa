import XCTest
@testable import VoxaNetworking
import VoxaPractice

final class VoxaBackendPracticeLanguageToolServiceTests: XCTestCase {
    private var service: VoxaBackendPracticeLanguageToolService!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        service = VoxaBackendPracticeLanguageToolService(
            baseURL: URL(string: "https://api.voxa.test")!,
            session: URLSession(configuration: config),
            correlationIDProvider: { "corr-test" }
        )
    }

    override func tearDown() {
        StubURLProtocol.reset()
        service = nil
        super.tearDown()
    }

    func testAskAnythingPostsContractAndDecodes() async throws {
        StubURLProtocol.handler = { request, _ in
            let json = """
            {"answer":"Use bonjour.","examples":[{"source":"hello","target":"bonjour","note":"neutral"}]}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let result = try await service.askAnything(
            question: "How do I say hello?",
            targetLanguage: "French",
            nativeLanguage: "English",
            accessToken: "access-token")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/language-tools/ask")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Correlation-Id"), "corr-test")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any]
        XCTAssertEqual(body?["targetLanguage"] as? String, "French")
        XCTAssertEqual(body?["nativeLanguage"] as? String, "English")
        XCTAssertEqual(body?["question"] as? String, "How do I say hello?")
        XCTAssertEqual(result.examples.first?.target, "bonjour")
    }

    func testTranslateImagePostsBase64AndMimeType() async throws {
        StubURLProtocol.handler = { request, _ in
            let json = """
            {"detectedText":"Sortie","sourceLanguage":"French","targetLanguage":"English","translatedText":"Exit","notes":"sign"}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let result = try await service.translateImage(
            imageBase64: "abcd",
            mimeType: "image/jpeg",
            sourceLanguage: nil,
            targetLanguage: "English",
            accessToken: "access-token")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/language-tools/translate-image")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any]
        XCTAssertEqual(body?["imageBase64"] as? String, "abcd")
        XCTAssertEqual(body?["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(result.translatedText, "Exit")
    }

    func testUnauthorizedMapsToAppSessionRequired() async {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"code":"app_session_required","message":"sign in","correlationId":"c","retryable":false}"#.utf8))
        }

        do {
            _ = try await service.vocabularyQuiz(
                targetLanguage: "French",
                proficiencyBand: "A1-A2",
                focus: nil,
                count: 5,
                accessToken: "expired")
            XCTFail("expected error")
        } catch let error as PracticeLanguageToolError {
            XCTAssertEqual(error, .appSessionRequired)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
