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
            correlationId: "corr-1",
            clientSecret: "s", model: "m", reasoningEffort: "low",
            expiresAt: Date(timeIntervalSince1970: 1000), settings: settings
        )
        XCTAssertTrue(credential.isExpired(asOf: Date(timeIntervalSince1970: 1001), leeway: 0))
        XCTAssertFalse(credential.isExpired(asOf: Date(timeIntervalSince1970: 900), leeway: 0))
    }

    func testTutorIntentPromptsMatchLearningWorkflow() {
        XCTAssertEqual(RealtimeTutorIntent.openPractice.title, "Speaking practice")
        XCTAssertEqual(RealtimeTutorIntent.openPractice.startButtonTitle, "Start talking")
        XCTAssertEqual(RealtimeTutorIntent.lesson(title: "Survival German").prompt, "Ready for Survival German?")
        XCTAssertEqual(RealtimeTutorIntent.lesson(title: "Survival German").startButtonTitle, "Start voice lesson")
        XCTAssertEqual(RealtimeTutorIntent.review(dueCount: 3).prompt, "Ready to review 3 due items?")
        XCTAssertEqual(RealtimeTutorIntent.review(dueCount: 3).startButtonTitle, "Start review")
        XCTAssertEqual(RealtimeTutorIntent.review(dueCount: 0).prompt, "Ready to review with your tutor?")
    }

    func testFocusedReviewIntentShapesPromptAndSettings() {
        let intent = RealtimeTutorIntent.review(dueCount: 2, focusTitle: "Pronunciation")
        let settings = RealtimeCoachingSettings(proficiencyBand: "A1-A2", targetLanguage: "de-DE")

        XCTAssertEqual(intent.title, "Pronunciation")
        XCTAssertEqual(intent.prompt, "Ready to practise pronunciation?")

        let applied = settings.applying(intent)
        XCTAssertEqual(applied.sessionIntent, "review")
        XCTAssertEqual(applied.focusTitle, "Pronunciation")
        XCTAssertEqual(applied.dueReviewCount, 2)
    }
}
