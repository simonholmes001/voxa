import XCTest
@testable import VoxaNetworking
import VoxaProfiles
import VoxaOnboarding

final class VoxaBackendLanguageSettingsServiceTests: XCTestCase {
    private var service: VoxaBackendLanguageSettingsService!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        service = VoxaBackendLanguageSettingsService(
            baseURL: URL(string: "https://api.voxa.test")!,
            session: URLSession(configuration: config),
            correlationIDProvider: { "corr-test" },
            accessTokenProvider: { "access-token" }
        )
    }

    override func tearDown() {
        StubURLProtocol.reset()
        service = nil
        super.tearDown()
    }

    private func profile() -> OnboardingProfile {
        OnboardingProfile(
            targetLanguage: "fr-FR", nativeLanguage: "de-DE", goals: ["travel", "work"],
            minutesPerDay: 42, placementLevel: .b1
        )
    }

    func testUpdatePostsOnboardingWithIfMatchAndReturnsNewVersion() async throws {
        StubURLProtocol.handler = { request, _ in
            let json = """
            {"profile":{"targetLanguage":"fr-FR","nativeLanguage":"de-DE","proficiencyLevel":"B1","goals":["travel","work"],"dailyMinutes":42},
             "activePlan":{"planId":"p","title":"t","knowledgeUnitIds":[]},"version":4,"correlationId":"c"}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let newVersion = try await service.update(languageKey: "fr-FR", profile: profile(), expectedVersion: 3)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/onboarding")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "3")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any]
        XCTAssertEqual(body?["targetLanguage"] as? String, "fr-FR")
        XCTAssertEqual(body?["goals"] as? [String], ["travel", "work"])
        XCTAssertEqual(body?["dailyMinutes"] as? Int, 42)

        XCTAssertEqual(newVersion, 4)
    }

    func testStaleVersionMapsToVersionConflict() async {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"code":"learner_state_version_conflict","message":"x","correlationId":"c","retryable":false}"#.utf8))
        }
        do {
            _ = try await service.update(languageKey: "fr-FR", profile: profile(), expectedVersion: 1)
            XCTFail("expected error")
        } catch let error as LanguageProfilesError {
            XCTAssertEqual(error, .versionConflict)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
