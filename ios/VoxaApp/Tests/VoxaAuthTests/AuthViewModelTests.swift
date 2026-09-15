import XCTest
@testable import VoxaAuth

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

private final class FakeAccountDataService: AccountDataService, @unchecked Sendable {
    var exportResult: Result<AccountDataExportFile, Error>
    var deleteResult: Result<AccountDeletionResult, Error>
    private(set) var exportedSession: AuthSession?
    private(set) var deletedSession: AuthSession?

    init(
        export: Result<AccountDataExportFile, Error> = .failure(AccountDataServiceError.unavailable),
        delete: Result<AccountDeletionResult, Error> = .failure(AccountDataServiceError.unavailable)
    ) {
        self.exportResult = export
        self.deleteResult = delete
    }

    func exportAccountData(_ session: AuthSession) async throws -> AccountDataExportFile {
        exportedSession = session
        return try exportResult.get()
    }

    func deleteAccount(_ session: AuthSession) async throws -> AccountDeletionResult {
        deletedSession = session
        return try deleteResult.get()
    }
}

@MainActor
final class AuthViewModelTests: XCTestCase {
    private func session(
        expiresAt: TimeInterval,
        refreshExpiresAt: TimeInterval = 9_000_000_000,
        access: String = "access"
    ) -> AuthSession {
        AuthSession(
            accessToken: access,
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: expiresAt),
            refreshTokenExpiresAt: Date(timeIntervalSince1970: refreshExpiresAt),
            userId: "user",
            tenantId: "tenant"
        )
    }

    private let proof = AppleIdentityProof(
        identityToken: Data("id".utf8),
        authorizationCode: Data("code".utf8),
        nonce: "nonce",
        userID: "user"
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
        let model = AuthViewModel(store: store, service: FakeAuthenticationService(exchange: .failure(AuthenticationServiceError.invalidAppleIdentity)))

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

    func testRestoreWithExpiredAccessRefreshesAndPersists() async throws {
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

    func testRestoreWithExpiredAccessAndFailedRefreshSignsOut() async {
        let expired = session(expiresAt: 100)
        let store = EphemeralSessionStore(session: expired)
        let model = AuthViewModel(
            store: store,
            service: FakeAuthenticationService(refresh: .failure(AuthenticationServiceError.sessionExpired)),
            now: { Date(timeIntervalSince1970: 500) }
        )

        await model.restore()

        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNil(try store.load())
    }

    func testRestoreWithDeadRefreshTokenSignsOutWithoutCallingRefresh() async throws {
        // Access expired AND refresh token itself expired -> no refresh attempt.
        let dead = session(expiresAt: 100, refreshExpiresAt: 200)
        let store = EphemeralSessionStore(session: dead)
        let service = FakeAuthenticationService(refresh: .success(session(expiresAt: 10_000)))
        let model = AuthViewModel(store: store, service: service, now: { Date(timeIntervalSince1970: 500) })

        await model.restore()

        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNil(try store.load())
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

    func testExportAccountDataUsesCurrentSignedInSession() async throws {
        let stored = session(expiresAt: 10_000)
        let export = AccountDataExportFile(filename: "voxa-account-data.json", data: Data("{}".utf8))
        let accountData = FakeAccountDataService(export: .success(export))
        let model = AuthViewModel(
            store: EphemeralSessionStore(session: stored),
            service: FakeAuthenticationService(),
            accountDataService: accountData,
            now: { Date(timeIntervalSince1970: 0) })
        await model.restore()

        let result = try await model.exportAccountData()

        XCTAssertEqual(result, export)
        XCTAssertEqual(accountData.exportedSession, stored)
        XCTAssertEqual(model.state, .signedIn(stored))
    }

    func testDeleteAccountClearsLocalSessionAfterBackendDeletion() async throws {
        let stored = session(expiresAt: 10_000)
        let store = EphemeralSessionStore(session: stored)
        let accountData = FakeAccountDataService(
            delete: .success(AccountDeletionResult(deleted: true, deletedLanguageProfileCount: 2)))
        let model = AuthViewModel(
            store: store,
            service: FakeAuthenticationService(),
            accountDataService: accountData,
            now: { Date(timeIntervalSince1970: 0) })
        await model.restore()

        let result = try await model.deleteAccount()

        XCTAssertTrue(result.deleted)
        XCTAssertEqual(result.deletedLanguageProfileCount, 2)
        XCTAssertEqual(accountData.deletedSession, stored)
        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNil(try store.load())
    }
}
