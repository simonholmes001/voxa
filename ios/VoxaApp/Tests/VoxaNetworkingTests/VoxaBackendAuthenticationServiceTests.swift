import XCTest
@testable import VoxaNetworking
import VoxaAuth

/// Intercepts URLSession requests so the auth client can be tested against
/// canned backend responses without a network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest, Data?) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static private(set) var lastRequest: URLRequest?
    nonisolated(unsafe) static private(set) var lastBody: Data?

    static func reset() {
        handler = nil
        lastRequest = nil
        lastBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(from: request)
        Self.lastRequest = request
        Self.lastBody = body
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request, body)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class VoxaBackendAuthenticationServiceTests: XCTestCase {
    private var service: VoxaBackendAuthenticationService!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        service = VoxaBackendAuthenticationService(
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

    private func ok(_ json: String) -> (URLRequest, Data?) throws -> (HTTPURLResponse, Data) {
        { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
    }

    private func error(status: Int, code: String) -> (URLRequest, Data?) throws -> (HTTPURLResponse, Data) {
        { request, _ in
            let body = #"{"code":"\#(code)","message":"nope","correlationId":"corr-test","retryable":false}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    private let sessionJSON = """
    {
      "correlationId": "corr-test",
      "tenantId": "tenant-default",
      "userId": "user-apple-subject",
      "accessToken": "app-access-token",
      "refreshToken": "app-refresh-token",
      "expiresAt": "2026-08-29T08:15:00Z",
      "refreshTokenExpiresAt": "2026-09-28T08:15:00Z"
    }
    """

    private let proof = AppleIdentityProof(
        identityToken: Data("apple-id-token".utf8),
        authorizationCode: Data("authorization-code".utf8),
        nonce: "nonce-123",
        userID: "user-apple-subject"
    )

    func testExchangePostsContractAndDecodesSession() async throws {
        StubURLProtocol.handler = ok(sessionJSON)

        let session = try await service.exchange(proof)

        // Request contract
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/auth/apple")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Correlation-Id"), "corr-test")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any]
        XCTAssertEqual(body?["identityToken"] as? String, "apple-id-token")
        XCTAssertEqual(body?["authorizationCode"] as? String, "authorization-code")
        XCTAssertEqual(body?["nonce"] as? String, "nonce-123")

        // Response mapping
        XCTAssertEqual(session.accessToken, "app-access-token")
        XCTAssertEqual(session.refreshToken, "app-refresh-token")
        XCTAssertEqual(session.userId, "user-apple-subject")
        XCTAssertEqual(session.tenantId, "tenant-default")
        XCTAssertEqual(session.expiresAt, ISO8601DateFormatter().date(from: "2026-08-29T08:15:00Z"))
        XCTAssertEqual(session.refreshTokenExpiresAt, ISO8601DateFormatter().date(from: "2026-09-28T08:15:00Z"))
    }

    func testRefreshPostsRefreshToken() async throws {
        StubURLProtocol.handler = ok(sessionJSON)
        let existing = AuthSession(
            accessToken: "old", refreshToken: "refresh-abc",
            expiresAt: .distantPast, refreshTokenExpiresAt: .distantFuture,
            userId: "u", tenantId: "t"
        )

        _ = try await service.refresh(existing)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/auth/refresh")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any]
        XCTAssertEqual(body?["refreshToken"] as? String, "refresh-abc")
    }

    func testInvalidatePostsLogout() async throws {
        StubURLProtocol.handler = ok(#"{"correlationId":"corr-test","revoked":true}"#)
        let existing = AuthSession(
            accessToken: "a", refreshToken: "refresh-xyz",
            expiresAt: .distantFuture, refreshTokenExpiresAt: .distantFuture,
            userId: "u", tenantId: "t"
        )

        try await service.invalidate(existing)

        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/api/auth/logout")
    }

    func testInvalidAppleIdentityMapsError() async {
        StubURLProtocol.handler = error(status: 401, code: "apple_identity_invalid")
        await assertThrows(AuthenticationServiceError.invalidAppleIdentity) {
            _ = try await service.exchange(proof)
        }
    }

    func testInvalidRefreshMapsSessionExpired() async {
        StubURLProtocol.handler = error(status: 401, code: "session_refresh_invalid")
        let existing = AuthSession(
            accessToken: "a", refreshToken: "r",
            expiresAt: .distantPast, refreshTokenExpiresAt: .distantFuture,
            userId: "u", tenantId: "t"
        )
        await assertThrows(AuthenticationServiceError.sessionExpired) {
            _ = try await service.refresh(existing)
        }
    }

    func testValidationErrorMapsValidation() async {
        StubURLProtocol.handler = error(status: 400, code: "validation_error")
        do {
            _ = try await service.exchange(proof)
            XCTFail("expected error")
        } catch let error as AuthenticationServiceError {
            guard case .validation = error else {
                return XCTFail("expected .validation, got \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testTransportFailureMapsTransport() async {
        StubURLProtocol.handler = { _, _ in throw URLError(.notConnectedToInternet) }
        await assertThrows(AuthenticationServiceError.transport) {
            _ = try await service.exchange(proof)
        }
    }

    private func assertThrows(
        _ expected: AuthenticationServiceError,
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as AuthenticationServiceError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
