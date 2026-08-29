import XCTest
@testable import VoxaAuth

final class AuthSessionTests: XCTestCase {
    private func session(expiresAt: TimeInterval) -> AuthSession {
        AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: expiresAt)
        )
    }

    func testIsExpiredWhenNowPastExpiry() {
        XCTAssertTrue(
            session(expiresAt: 100).isExpired(asOf: Date(timeIntervalSince1970: 200), leeway: 0)
        )
    }

    func testIsNotExpiredWhenWithinValidity() {
        XCTAssertFalse(
            session(expiresAt: 1000).isExpired(asOf: Date(timeIntervalSince1970: 500), leeway: 0)
        )
    }

    func testLeewayTreatsSoonToExpireSessionAsExpired() {
        XCTAssertTrue(
            session(expiresAt: 1000).isExpired(asOf: Date(timeIntervalSince1970: 950), leeway: 60)
        )
    }

    func testEphemeralStoreRoundTrips() throws {
        let store = EphemeralSessionStore()
        let session = session(expiresAt: 1000)
        try store.save(session)
        XCTAssertEqual(try store.load(), session)
        try store.clear()
        XCTAssertNil(try store.load())
    }
}
