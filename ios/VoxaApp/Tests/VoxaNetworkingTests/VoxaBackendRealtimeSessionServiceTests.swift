import XCTest
@testable import VoxaNetworking
import VoxaRealtime

final class VoxaBackendRealtimeSessionServiceTests: XCTestCase {
    private var service: VoxaBackendRealtimeSessionService!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        service = VoxaBackendRealtimeSessionService(
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

    private let settings = RealtimeCoachingSettings(
        coachingMode: "tutor", proficiencyBand: "B1-B2", targetLanguage: "fr-FR"
    )

    private let responseJSON = """
    {
      "correlationId": "corr-123",
      "clientSecret": "short-lived-client-token",
      "model": "gpt-realtime-2.1",
      "reasoningEffort": "low",
      "expiresAt": "2026-08-29T08:20:00Z",
      "settings": {
        "coachingMode": "tutor",
        "proficiencyBand": "B1-B2",
        "targetLanguage": "fr-FR",
        "sessionIntent": "lesson",
        "focusTitle": "Survival French",
        "dueReviewCount": null
      }
    }
    """

    func testCreateSessionPostsContractAndDecodes() async throws {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(self.responseJSON.utf8))
        }

        let credential = try await service.createSession(settings, accessToken: "access-token")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/realtime/session")
        XCTAssertEqual(request.httpMethod, "POST")
        // Authorization must be the caller's bearer token
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Correlation-Id"), "corr-test")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any]
        XCTAssertEqual(body?["coachingMode"] as? String, "tutor")
        XCTAssertEqual(body?["proficiencyBand"] as? String, "B1-B2")
        XCTAssertEqual(body?["targetLanguage"] as? String, "fr-FR")

        XCTAssertEqual(credential.correlationId, "corr-123")
        XCTAssertEqual(credential.clientSecret, "short-lived-client-token")
        XCTAssertEqual(credential.model, "gpt-realtime-2.1")
        XCTAssertEqual(credential.reasoningEffort, "low")
        XCTAssertEqual(credential.settings.targetLanguage, "fr-FR")
        XCTAssertEqual(credential.expiresAt, ISO8601DateFormatter().date(from: "2026-08-29T08:20:00Z"))
    }

    func testCreateSessionPostsLearningIntentFields() async throws {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(self.responseJSON.utf8))
        }

        let lessonSettings = RealtimeCoachingSettings(
            proficiencyBand: "B1-B2",
            targetLanguage: "fr-FR",
            sessionIntent: "lesson",
            focusTitle: "Survival French"
        )

        _ = try await service.createSession(lessonSettings, accessToken: "access-token")

        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any]
        XCTAssertEqual(body?["sessionIntent"] as? String, "lesson")
        XCTAssertEqual(body?["focusTitle"] as? String, "Survival French")
    }

    func testCompleteSessionPostsLearningSessionContract() async throws {
        StubURLProtocol.handler = { request, body in
            XCTAssertEqual(request.url?.path, "/api/session/complete")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Correlation-Id"), "corr-test")

            let object = try JSONSerialization.jsonObject(with: try XCTUnwrap(body)) as? [String: Any]
            XCTAssertEqual(object?["sessionId"] as? String, "corr-123")
            XCTAssertEqual(object?["durationSeconds"] as? Int, 420)
            XCTAssertEqual(object?["sessionIntent"] as? String, "lesson")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"correlationId":"corr-test","version":2}"#.utf8))
        }

        try await service.completeSession(
            RealtimeSessionCompletion(
                sessionId: "corr-123",
                durationSeconds: 420,
                sessionIntent: "lesson"
            ),
            accessToken: "access-token")
    }

    func testUnauthorizedMapsAppSessionRequired() async {
        StubURLProtocol.handler = { request, _ in
            let body = #"{"code":"app_session_required","message":"nope","correlationId":"c","retryable":false}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }

        do {
            _ = try await service.createSession(settings, accessToken: "t")
            XCTFail("expected error")
        } catch let error as RealtimeSessionError {
            XCTAssertEqual(error, .appSessionRequired)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testTransportFailureMapsTransport() async {
        StubURLProtocol.handler = { _, _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await service.createSession(settings, accessToken: "t")
            XCTFail("expected error")
        } catch let error as RealtimeSessionError {
            XCTAssertEqual(error, .transport)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
