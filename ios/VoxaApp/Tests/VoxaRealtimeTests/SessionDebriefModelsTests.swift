import XCTest
@testable import VoxaRealtime

final class SessionDebriefModelsTests: XCTestCase {

    // MARK: - Recommended-drill → intent mapping

    func testEveryBackendSessionIntentStringMapsToATutorIntent() {
        // Contract with the backend router: any snake_case intent the debrief
        // recommends must resolve into a launchable RealtimeTutorIntent so
        // the "Start this drill" button on the debrief always works.
        XCTAssertEqual(recommendation("open_practice").intent, .openPractice)
        XCTAssertEqual(recommendation("practice").intent, .openPractice)
        XCTAssertEqual(recommendation("guided_lesson", focus: "Past tense").intent,
                       .lesson(title: "Past tense"))
        XCTAssertEqual(recommendation("lesson", focus: "").intent, .lesson(title: nil))
        XCTAssertEqual(recommendation("review").intent, .review(dueCount: 0))
        XCTAssertEqual(recommendation("pronunciation_drill", focus: "French u").intent,
                       .pronunciationDrill(focusTitle: "French u"))
        XCTAssertEqual(recommendation("roleplay", focus: "Bar order").intent,
                       .roleplay(scenarioTitle: "Bar order"))
        XCTAssertEqual(recommendation("mistakes_replay").intent, .mistakesReplay())
        XCTAssertEqual(recommendation("vocabulary_drill").intent, .vocabularyDrill())
        XCTAssertEqual(recommendation("listening_practice").intent, .listeningPractice())
        XCTAssertEqual(recommendation("key_language", focus: "Passé composé").intent,
                       .keyLanguage(topic: "Passé composé"))
    }

    func testUnknownIntentFallsBackToOpenPracticeSoTheDrillButtonAlwaysWorks() {
        XCTAssertEqual(recommendation("some_new_intent_the_client_does_not_know").intent, .openPractice)
    }

    func testRoleplayWithoutFocusFallsBackToASafePlaceholderScenario() {
        // The DebriefRecommendedDrill.intent computed property needs a
        // scenario title to build the intent; a safe fallback keeps the
        // "Start this drill" button clickable even if the assessor forgot.
        let drill = recommendation("roleplay", focus: "")
        if case let .roleplay(scenario) = drill.intent {
            XCTAssertFalse(scenario.isEmpty)
        } else {
            XCTFail("Expected .roleplay intent, got \(drill.intent)")
        }
    }

    func testKeyLanguageWithoutFocusFallsBackToASafePlaceholderTopic() {
        let drill = recommendation("key_language", focus: "")
        if case let .keyLanguage(topic) = drill.intent {
            XCTAssertFalse(topic.isEmpty)
        } else {
            XCTFail("Expected .keyLanguage intent, got \(drill.intent)")
        }
    }

    // MARK: - Helpers

    private func recommendation(
        _ intent: String,
        focus: String = ""
    ) -> DebriefRecommendedDrill {
        DebriefRecommendedDrill(activityIntent: intent, focusTitle: focus, reason: "")
    }
}
