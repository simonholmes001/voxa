import XCTest
@testable import VoxaAuth

/// Configurable fake backend service for exercising the session lifecycle.
private final class FakeAuthenticationService: AuthenticationService, @unchecked Sendable {
    var exchangeResult: Result<AuthSession, Error>
    var refreshResult: Result<AuthSession, Error>
    private(set) var invalidateCount = 0

    init(
        exchange: Result<AuthSession, Error> = .failure(AuthenticationServiceError.unavailable),
        refresh: Result<AuthSession, Error> = .failure(AuthenticationServiceError.unavailable)
    ) {
        self.exchangeResult = exchange
        self.refreshResult = refresh
    }

    func exchange(_ proof: AppleIdentityProof) async throws -> AuthSession {
        try exchangeResult.get()
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        try refreshResult.get()
    }

    func invalidate(_ session: AuthSession) async throws {
        invalidateCount += 1
    }
}

@MainActor
final class AuthViewModelTests: XCTestCase {
    private func session(expiresAt: TimeInterval, access: String = "access") -> AuthSession {
        AuthSession(
            accessToken: access,
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: expiresAt)
        )
    }

    private let proof = AppleIdentityProof(
        userID: "user",
        identityToken: Data("id".utf8),
        authorizationCode: Data("code".utf8)
    )

    func testSignInSuccessPersistsSessionAndSignsIn() async throws {
        let store = EphemeralSessionStore()
        let expected = session(expiresAt: 10_000)
        let model = AuthViewModel(store: store, service: FakeAuthenticationService(exchange: .success(expected)))

        await model.signIn(with: proof)

        XCTAssertEqual(model.state, .signedIn(expected))
        XCTAssertEqual(try store.load(), expected)
    }

    func testSignInFailureSetsFailedAndDoesNotPersist() async throws {
        let store = EphemeralSessionStore()
        let model = AuthViewModel(store: store, service: FakeAuthenticationService(exchange: .failure(AuthenticationServiceError.unavailable)))

        await model.signIn(with: proof)

        guard case .failed = model.state else {
            return XCTFail("expected .failed, got \(model.state)")
        }
        XCTAssertNil(try store.load())
    }

    func testRestoreWithValidSessionSignsIn() async {
        let stored = session(expiresAt: 10_000)
        let model = AuthViewModel(
            store: EphemeralSessionStore(session: stored),
            service: FakeAuthenticationService(),
            now: { Date(timeIntervalSince1970: 0) }
        )

        await model.restore()

        XCTAssertEqual(model.state, .signedIn(stored))
    }

    func testRestoreWithExpiredSessionRefreshesAndPersists() async throws {
        let expired = session(expiresAt: 100)
        let refreshed = session(expiresAt: 10_000, access: "fresh")
        let store = EphemeralSessionStore(session: expired)
        let model = AuthViewModel(
            store: store,
            service: FakeAuthenticationService(refresh: .success(refreshed)),
            now: { Date(timeIntervalSince1970: 500) }
        )

        await model.restore()

        XCTAssertEqual(model.state, .signedIn(refreshed))
        XCTAssertEqual(try store.load(), refreshed)
    }

    func testRestoreWithExpiredSessionAndFailedRefreshSignsOut() async {
        let expired = session(expiresAt: 100)
        let model = AuthViewModel(
            store: EphemeralSessionStore(session: expired),
            service: FakeAuthenticationService(refresh: .failure(AuthenticationServiceError.unavailable)),
            now: { Date(timeIntervalSince1970: 500) }
        )

        await model.restore()

        XCTAssertEqual(model.state, .signedOut)
    }

    func testSignOutInvalidatesBackendAndClearsStore() async throws {
        let stored = session(expiresAt: 10_000)
        let store = EphemeralSessionStore(session: stored)
        let service = FakeAuthenticationService()
        let model = AuthViewModel(store: store, service: service, now: { Date(timeIntervalSince1970: 0) })
        await model.restore()

        await model.signOut()

        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNil(try store.load())
        XCTAssertEqual(service.invalidateCount, 1)
    }
}
