import XCTest
@testable import VoxaNetworking
import VoxaOnboarding

final class VoxaBackendOnboardingServiceTests: XCTestCase {
    private var service: VoxaBackendOnboardingService!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        service = VoxaBackendOnboardingService(
            baseURL: URL(string: "https://api.voxa.test")!,
            session: URLSession(configuration: config),
            correlationIDProvider: { "corr-test" },
            accessTokenProvider: { "app-access-token" }
        )
    }

    override func tearDown() {
        StubURLProtocol.reset()
        service = nil
        super.tearDown()
    }

    func testSubmitPostsProfileAndDecodesBackendSuccessResponse() async throws {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.submitResponseJSON.utf8))
        }

        try await service.submit(OnboardingProfile(
            targetLanguage: "French",
            nativeLanguage: "English",
            goals: ["travel", "Order coffee"],
            minutesPerDay: 20,
            placementLevel: .b1
        ))

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/onboarding")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer app-access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Correlation-Id"), "corr-test")

        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any]
        XCTAssertEqual(body?["targetLanguage"] as? String, "French")
        XCTAssertEqual(body?["nativeLanguage"] as? String, "English")
        XCTAssertEqual(body?["proficiencyLevel"] as? String, "B1")
        XCTAssertEqual(body?["goals"] as? [String], ["travel", "Order coffee"])
        XCTAssertEqual(body?["dailyMinutes"] as? Int, 20)
    }

    func testResumeDecodesProfileForCrossDeviceContinuation() async throws {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.submitResponseJSON.utf8))
        }

        let profile = try await service.resume()

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/session/resume")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer app-access-token")

        XCTAssertEqual(profile?.targetLanguage, "French")
        XCTAssertEqual(profile?.nativeLanguage, "English")
        XCTAssertEqual(profile?.goals, ["travel"])
        XCTAssertEqual(profile?.minutesPerDay, 20)
        XCTAssertEqual(profile?.placementLevel, .b1)
    }

    func testResumeCheckpointDecodesPlanLessonReviewQueueAndRecentSessions() async throws {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.resumeCheckpointJSON.utf8))
        }

        let checkpoint = try await service.resumeCheckpoint()

        XCTAssertEqual(checkpoint?.profile.targetLanguage, "de-DE")
        XCTAssertEqual(checkpoint?.activePlan?.title, "Survival German")
        XCTAssertEqual(checkpoint?.activePlan?.knowledgeUnitIds, ["station-directions", "tickets"])
        XCTAssertEqual(checkpoint?.currentLesson?.lessonId, "lesson-1")
        XCTAssertEqual(checkpoint?.currentLesson?.knowledgeUnitId, "station-directions")
        XCTAssertEqual(checkpoint?.currentLesson?.stepIndex, 3)
        XCTAssertEqual(checkpoint?.reviewQueue.first?.knowledgeUnitId, "ticket")
        XCTAssertEqual(checkpoint?.reviewQueue.first?.priority, 2)
        XCTAssertEqual(checkpoint?.recentSessions.first?.durationSeconds, 600)
        XCTAssertEqual(checkpoint?.recentSessions.first?.lessonId, "lesson-1")
    }

    func testResumeCheckpointSuppressesEmptyPlanLessonAndQueueSentinels() async throws {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.emptyCheckpointJSON.utf8))
        }

        let checkpoint = try await service.resumeCheckpoint()

        XCTAssertNil(checkpoint?.activePlan)
        XCTAssertNil(checkpoint?.currentLesson)
        XCTAssertEqual(checkpoint?.reviewQueue, [])
        XCTAssertEqual(checkpoint?.recentSessions, [])
    }

    func testResumeTransportFailureMapsToTransportUnavailable() async {
        StubURLProtocol.handler = { _, _ in throw URLError(.notConnectedToInternet) }

        do {
            _ = try await service.resume()
            XCTFail("expected transport failure")
        } catch {
            XCTAssertEqual(error as? OnboardingServiceError, .transportUnavailable)
        }
    }

    func testResumeUnauthorizedDoesNotMapToTransportUnavailable() async {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await service.resume()
            XCTFail("expected auth failure")
        } catch {
            XCTAssertEqual(error as? OnboardingServiceError, .authenticationRequired)
        }
    }

    func testResumeInvalidPayloadDoesNotMapToTransportUnavailable() async {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"not":"the contract"}"#.utf8))
        }

        do {
            _ = try await service.resume()
            XCTFail("expected invalid response")
        } catch {
            XCTAssertEqual(error as? OnboardingServiceError, .invalidResponse)
        }
    }

    private static let submitResponseJSON = """
    {
      "correlationId": "corr-test",
      "profile": {
        "targetLanguage": "French",
        "nativeLanguage": "English",
        "proficiencyLevel": "B1",
        "goals": ["travel"],
        "dailyMinutes": 20
      },
      "activePlan": {
        "planId": "plan-b1",
        "title": "Intermediate Expansion",
        "knowledgeUnitIds": ["opinions", "stories", "travel"]
      },
      "version": 1
    }
    """

    private static let resumeCheckpointJSON = """
    {
      "correlationId": "corr-test",
      "version": 2,
      "profile": {
        "targetLanguage": "de-DE",
        "nativeLanguage": "en-US",
        "proficiencyLevel": "A1",
        "goals": ["travel"],
        "dailyMinutes": 30
      },
      "activePlan": {
        "planId": "plan-1",
        "title": "Survival German",
        "knowledgeUnitIds": ["station-directions", "tickets"]
      },
      "currentLesson": {
        "lessonId": "lesson-1",
        "knowledgeUnitId": "station-directions",
        "stepIndex": 3,
        "updatedAt": "2026-08-29T07:00:00Z"
      },
      "reviewQueue": [
        {
          "knowledgeUnitId": "ticket",
          "dueAt": "2026-08-30T07:00:00Z",
          "priority": 2
        }
      ],
      "recentSessions": [
        {
          "sessionId": "session-1",
          "startedAt": "2026-08-29T07:00:00Z",
          "durationSeconds": 600,
          "lessonId": "lesson-1"
        }
      ]
    }
    """

    private static let emptyCheckpointJSON = """
    {
      "correlationId": "corr-test",
      "version": 2,
      "profile": {
        "targetLanguage": "de-DE",
        "nativeLanguage": "en-US",
        "proficiencyLevel": "A1",
        "goals": ["travel"],
        "dailyMinutes": 30
      },
      "activePlan": {
        "planId": "",
        "title": "",
        "knowledgeUnitIds": []
      },
      "currentLesson": {
        "lessonId": "",
        "knowledgeUnitId": "",
        "stepIndex": 0,
        "updatedAt": "1970-01-01T00:00:00Z"
      },
      "reviewQueue": [
        {
          "knowledgeUnitId": "",
          "dueAt": "1970-01-01T00:00:00Z",
          "priority": 0
        }
      ],
      "recentSessions": [
        {
          "sessionId": "",
          "startedAt": "1970-01-01T00:00:00Z",
          "durationSeconds": 0,
          "lessonId": ""
        }
      ]
    }
    """
}
