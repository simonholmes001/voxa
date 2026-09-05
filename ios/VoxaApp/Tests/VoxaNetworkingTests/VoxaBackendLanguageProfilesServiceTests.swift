import XCTest
@testable import VoxaNetworking
import VoxaProfiles

final class VoxaBackendLanguageProfilesServiceTests: XCTestCase {
    private var service: VoxaBackendLanguageProfilesService!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        service = VoxaBackendLanguageProfilesService(
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
