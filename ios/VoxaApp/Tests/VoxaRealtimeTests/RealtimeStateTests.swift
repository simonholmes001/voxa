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

    /// Locks in the client-side half of the SessionIntent contract: every new
    /// activity emits the snake_case string that the backend router
    /// (`OpenAiRealtimeClientSecretIssuer.ResolvePromptRef`) matches on. A
    /// mismatch here would silently fall the backend back to open-practice.
    func testEveryTutorIntentEmitsBackendRecognisedSessionIntentString() {
        let base = RealtimeCoachingSettings(proficiencyBand: "A1-A2", targetLanguage: "fr-FR")

        XCTAssertEqual(base.applying(.openPractice).sessionIntent, "open_practice")
        XCTAssertEqual(base.applying(.lesson(title: "Past tense")).sessionIntent, "guided_lesson")
        XCTAssertEqual(base.applying(.review(dueCount: 5)).sessionIntent, "review")
        XCTAssertEqual(base.applying(.pronunciationDrill()).sessionIntent, "pronunciation_drill")
        XCTAssertEqual(base.applying(.roleplay(scenarioTitle: "Café order")).sessionIntent, "roleplay")
        XCTAssertEqual(base.applying(.mistakesReplay()).sessionIntent, "mistakes_replay")
        XCTAssertEqual(base.applying(.vocabularyDrill()).sessionIntent, "vocabulary_drill")
        XCTAssertEqual(base.applying(.listeningPractice()).sessionIntent, "listening_practice")
        XCTAssertEqual(base.applying(.keyLanguage(topic: "Past tense")).sessionIntent, "key_language")
    }

    func testActivitiesThatCarryATitleForwardItAsFocusTitle() {
        let base = RealtimeCoachingSettings(proficiencyBand: "A1-A2", targetLanguage: "fr-FR")

        XCTAssertEqual(
            base.applying(.roleplay(scenarioTitle: "Order coffee in Paris")).focusTitle,
            "Order coffee in Paris")
        XCTAssertEqual(
            base.applying(.keyLanguage(topic: "French past tense")).focusTitle,
            "French past tense")
        XCTAssertEqual(
            base.applying(.pronunciationDrill(focusTitle: "French u vowel")).focusTitle,
            "French u vowel")
        XCTAssertNil(base.applying(.pronunciationDrill()).focusTitle)
    }
}
