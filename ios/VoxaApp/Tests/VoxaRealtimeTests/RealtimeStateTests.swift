import XCTest
@testable import VoxaRealtime

final class RealtimeStateTests: XCTestCase {
    func testBusyStates() {
        XCTAssertTrue(RealtimeConnectionState.requestingSession.isBusy)
        XCTAssertTrue(RealtimeConnectionState.connecting.isBusy)
        XCTAssertTrue(RealtimeConnectionState.connected.isBusy)
        XCTAssertFalse(RealtimeConnectionState.idle.isBusy)
        XCTAssertFalse(RealtimeConnectionState.ended.isBusy)
        XCTAssertFalse(RealtimeConnectionState.failed("x").isBusy)
    }

    func testCredentialExpiry() {
        let settings = RealtimeCoachingSettings(proficiencyBand: "A1-A2", targetLanguage: "fr-FR")
        let credential = RealtimeSessionCredential(
            clientSecret: "s", model: "m", reasoningEffort: "low",
            expiresAt: Date(timeIntervalSince1970: 1000), settings: settings
        )
        XCTAssertTrue(credential.isExpired(asOf: Date(timeIntervalSince1970: 1001), leeway: 0))
        XCTAssertFalse(credential.isExpired(asOf: Date(timeIntervalSince1970: 900), leeway: 0))
    }
}
