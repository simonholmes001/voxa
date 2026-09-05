import XCTest
@testable import VoxaNetworking
import VoxaOnboarding
import VoxaProfiles

final class VoxaBackendLanguageProfilesServiceTests: XCTestCase {
    private var service: VoxaBackendLanguageProfilesService!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        service = VoxaBackendLanguageProfilesService(
            baseURL: URL(string: "https://api.voxa.test")!,
            session: URLSession(configuration: urlSessionConfiguration),
            correlationIDProvider: { "corr-test" },
            accessTokenProvider: { "access-token" }
        )
    }

    override func tearDown() {
        StubURLProtocol.reset()
        service = nil
        super.tearDown()
    }

    private var urlSessionConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return config
    }

    private let listJSON = """
    {
      "correlationId": "corr-123",
      "activeLanguageKey": "fr-FR",
      "profiles": [
        {
          "languageKey": "fr-FR",
          "displayName": "French",
          "isComplete": true,
          "profile": {
            "targetLanguage": "fr-FR",
            "nativeLanguage": "en-US",
            "proficiencyLevel": "A1",
            "goals": ["travel"],
            "dailyMinutes": 15
          },
          "version": 3
        }
      ]
    }
    """

    func testListDecodesProfilesAndActiveKey() async throws {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(self.listJSON.utf8))
        }

        let result = try await service.list()

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/language-profiles")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")

        XCTAssertEqual(result.activeLanguageKey, "fr-FR")
        XCTAssertEqual(result.profiles.count, 1)
        let fr = try XCTUnwrap(result.profiles.first)
        XCTAssertEqual(fr.languageKey, "fr-FR")
        XCTAssertEqual(fr.displayName, "French")
        XCTAssertTrue(fr.isComplete)
        XCTAssertEqual(fr.version, 3)
        XCTAssertEqual(fr.profile.goals, ["travel"])
        XCTAssertEqual(fr.profile.minutesPerDay, 15)
        XCTAssertEqual(fr.profile.placementLevel, .a1)
    }

    func testListUsesFiniteRequestTimeout() async throws {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(self.listJSON.utf8))
        }

        _ = try await service.list()

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.timeoutInterval, 15, accuracy: 0.01)
    }

    func testProductionResponseDrivesProfileSelectionState() async throws {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(self.listJSON.utf8))
        }
        let service = VoxaBackendLanguageProfilesService(
            baseURL: URL(string: "https://api.voxa.test")!,
            session: URLSession(configuration: self.urlSessionConfiguration),
            correlationIDProvider: { "corr-integration" },
            accessTokenProvider: { "access-token" }
        )
        let model = await MainActor.run { ProfileSelectionViewModel(service: service) }

        await model.load()

        let expected = LanguageProfile(
            languageKey: "fr-FR",
            displayName: "French",
            isComplete: true,
            profile: OnboardingProfile(
                targetLanguage: "fr-FR",
                nativeLanguage: "en-US",
                goals: ["travel"],
                minutesPerDay: 15,
                placementLevel: .a1
            ),
            version: 3
        )
        let (state, activeLanguageKey) = await MainActor.run { (model.state, model.activeLanguageKey) }
        XCTAssertEqual(state, .single(expected))
        XCTAssertEqual(activeLanguageKey, "fr-FR")
    }

    func testMalformedProductionProfileDoesNotLeaveSelectionWaiting() async {
        StubURLProtocol.handler = { request, _ in
            let json = #"{"correlationId":"c","activeLanguageKey":"fr-FR","profiles":[{"languageKey":"fr-FR","displayName":"French","isComplete":true,"profile":{"targetLanguage":"fr-FR","nativeLanguage":"en-US","goals":["travel"],"minutesPerDay":15,"proficiencyLevel":"not-a-cefr-level"},"version":3}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        do {
            _ = try await service.list()
            XCTFail("expected malformed profile to be rejected")
        } catch let error as LanguageProfilesError {
            XCTAssertEqual(error, .transport)
        } catch {
            XCTFail("unexpected (error)")
        }
    }

    func testEmptyProfilesIsValid() async throws {
        StubURLProtocol.handler = { request, _ in
            let json = #"{"correlationId":"c","activeLanguageKey":null,"profiles":[]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let result = try await service.list()

        XCTAssertNil(result.activeLanguageKey)
        XCTAssertTrue(result.profiles.isEmpty)
    }

    func testSelectPostsToEncodedPathAndReturnsActiveKey() async throws {
        StubURLProtocol.handler = { request, _ in
            let json = #"{"correlationId":"c","activeLanguageKey":"es-ES"}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let active = try await service.selectActive(languageKey: "es-ES")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/language-profiles/es-ES/select")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(active, "es-ES")
    }

    func testUnauthorizedMapsToAuthenticationRequired() async {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"code":"app_session_required","message":"x","correlationId":"c","retryable":false}"#.utf8))
        }
        await assertListThrows(.authenticationRequired)
    }

    func testMissingAccessTokenMapsToAuthenticationRequiredBeforeNetworkCall() async {
        let service = VoxaBackendLanguageProfilesService(
            baseURL: URL(string: "https://api.voxa.test")!,
            session: URLSession(configuration: urlSessionConfiguration),
            correlationIDProvider: { "corr-no-token" },
            accessTokenProvider: { nil }
        )

        do {
            _ = try await service.list()
            XCTFail("expected authentication error")
        } catch let error as LanguageProfilesError {
            XCTAssertEqual(error, .authenticationRequired)
            XCTAssertNil(StubURLProtocol.lastRequest)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testUnknownLanguageMapsTo404() async {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"code":"unknown_language","message":"x","correlationId":"c","retryable":false}"#.utf8))
        }
        do {
            _ = try await service.selectActive(languageKey: "xx-XX")
            XCTFail("expected error")
        } catch let error as LanguageProfilesError {
            XCTAssertEqual(error, .unknownLanguage)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testVersionConflictMapsTo409() async {
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"code":"learner_state_version_conflict","message":"x","correlationId":"c","retryable":false}"#.utf8))
        }
        await assertListThrows(.versionConflict)
    }

    private func assertListThrows(_ expected: LanguageProfilesError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await service.list()
            XCTFail("expected error", file: file, line: line)
        } catch let error as LanguageProfilesError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }
}
