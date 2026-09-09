import XCTest
@testable import VoxaHome
import VoxaRealtime

final class PracticeHubTests: XCTestCase {

    // MARK: - Today card

    func testTodayCardRecommendsReviewWhenDueItemsExist() {
        let card = PracticeHub.todayCard(for: summary(dueReviewCount: 3))
        XCTAssertEqual(card.recommendation, .review(dueCount: 3))
        XCTAssertEqual(card.title, "Review 3 due items")
        XCTAssertEqual(card.actionTitle, "Start review")
    }

    func testTodayCardPluraliseCorrectlyForOneDueItem() {
        let card = PracticeHub.todayCard(for: summary(dueReviewCount: 1))
        XCTAssertEqual(card.title, "Review 1 due item")
    }

    func testTodayCardRecommendsContinueLessonWhenNoReviewsButActiveLesson() {
        let card = PracticeHub.todayCard(
            for: summary(dueReviewCount: 0, currentLessonTitle: "Past tense"))
        XCTAssertEqual(card.recommendation, .continueLesson(title: "Past tense"))
        XCTAssertEqual(card.title, "Continue: Past tense")
        XCTAssertEqual(card.actionTitle, "Continue lesson")
    }

    func testTodayCardFallsBackToActivePlanTitleWhenNoCurrentLesson() {
        let card = PracticeHub.todayCard(
            for: summary(dueReviewCount: 0, activePlanTitle: "Everyday French"))
        XCTAssertEqual(card.recommendation, .continueLesson(title: "Everyday French"))
    }

    func testTodayCardFallsBackToFreeConversationWhenNothingElse() {
        let card = PracticeHub.todayCard(for: summary(dueReviewCount: 0))
        XCTAssertEqual(card.recommendation, .freeConversation)
        XCTAssertEqual(card.title, "Start speaking")
        XCTAssertEqual(card.actionTitle, "Start talking")
    }

    func testTodayCardFallsBackToFreeConversationForMissingSummary() {
        let card = PracticeHub.todayCard(for: nil)
        XCTAssertEqual(card.recommendation, .freeConversation)
    }

    func testTodayCardIgnoresBlankLessonAndPlanTitles() {
        let card = PracticeHub.todayCard(
            for: summary(dueReviewCount: 0, currentLessonTitle: "   ", activePlanTitle: "  "))
        XCTAssertEqual(card.recommendation, .freeConversation)
    }

    // MARK: - Today intent

    func testTodayIntentForReviewCarriesTheDueCount() {
        let intent = PracticeHub.todayIntent(for: .review(dueCount: 5))
        XCTAssertEqual(intent, .review(dueCount: 5))
    }

    func testTodayIntentForContinueLessonCarriesTheTitle() {
        let intent = PracticeHub.todayIntent(for: .continueLesson(title: "Past tense"))
        XCTAssertEqual(intent, .lesson(title: "Past tense"))
    }

    func testTodayIntentForFreeConversationIsOpenPractice() {
        XCTAssertEqual(PracticeHub.todayIntent(for: .freeConversation), .openPractice)
    }

    // MARK: - Tile grid

    func testTilesForFreshLearnerShowsSixCoreTilesAndReview() {
        let tiles = PracticeHub.tiles(for: nil).map(\.kind)
        XCTAssertEqual(tiles, [
            .freeConversation,
            .fixRecentMistakes,
            .pronunciation,
            .listening,
            .vocabulary,
            .roleplay,
            .review,
        ])
    }

    func testTilesForLearnerWithActivePlanIncludesGuidedLesson() {
        let tiles = PracticeHub.tiles(
            for: summary(activePlanTitle: "Everyday French"))
        XCTAssertTrue(tiles.contains(where: { $0.kind == .guidedLesson }))
    }

    func testTilesForLearnerWithCurrentLessonIncludesKeyLanguage() {
        let tiles = PracticeHub.tiles(
            for: summary(currentLessonTitle: "Past tense"))
        XCTAssertTrue(tiles.contains(where: { $0.kind == .keyLanguage }))
    }

    func testTilesForLearnerWithoutCurrentLessonHidesKeyLanguage() {
        let tiles = PracticeHub.tiles(for: summary(activePlanTitle: "Everyday French"))
        XCTAssertFalse(tiles.contains(where: { $0.kind == .keyLanguage }))
    }

    func testTileTitlesAreDistinct() {
        // Guards against a copy-paste bug that would give two tiles the same
        // label — the tap dispatch is fine but the UX would be confusing.
        let titles = PracticeHubTile.Kind.allCases.map { PracticeHubTile(kind: $0).title }
        XCTAssertEqual(Set(titles).count, titles.count, "duplicate tile titles: \(titles)")
    }

    // MARK: - Tile intent

    func testFreeConversationTileLaunchesOpenPractice() {
        XCTAssertEqual(PracticeHub.intent(for: .freeConversation, summary: nil), .openPractice)
    }

    func testFixMistakesTileLaunchesMistakesReplay() {
        XCTAssertEqual(PracticeHub.intent(for: .fixRecentMistakes, summary: nil), .mistakesReplay())
    }

    func testPronunciationTileLaunchesPronunciationDrill() {
        XCTAssertEqual(PracticeHub.intent(for: .pronunciation, summary: nil), .pronunciationDrill())
    }

    func testListeningTileLaunchesListeningPractice() {
        XCTAssertEqual(PracticeHub.intent(for: .listening, summary: nil), .listeningPractice())
    }

    func testVocabularyTileLaunchesVocabularyDrill() {
        XCTAssertEqual(PracticeHub.intent(for: .vocabulary, summary: nil), .vocabularyDrill())
    }

    func testRoleplayTileLaunchesRoleplayWithPlaceholderScenarioUntilB4() {
        // B4 will replace this with a scenario library; the placeholder must
        // still be a real, present-tense scenario title so the tutor prompt
        // renders a plausible opening.
        let intent = PracticeHub.intent(for: .roleplay, summary: nil)
        XCTAssertEqual(intent, .roleplay(scenarioTitle: "An everyday café order"))
    }

    func testKeyLanguageTileUsesCurrentLessonTitleWhenAvailable() {
        let intent = PracticeHub.intent(
            for: .keyLanguage,
            summary: summary(currentLessonTitle: "Past tense"))
        XCTAssertEqual(intent, .keyLanguage(topic: "Past tense"))
    }

    func testKeyLanguageTileFallsBackToActivePlanTitle() {
        let intent = PracticeHub.intent(
            for: .keyLanguage,
            summary: summary(currentLessonTitle: nil, activePlanTitle: "Everyday French"))
        XCTAssertEqual(intent, .keyLanguage(topic: "Everyday French"))
    }

    func testKeyLanguageTileFallsBackToSafeDefaultWhenNoContext() {
        let intent = PracticeHub.intent(for: .keyLanguage, summary: nil)
        XCTAssertEqual(intent, .keyLanguage(topic: "the language coming up next"))
    }

    func testGuidedLessonTileForwardsCurrentLessonTitle() {
        let intent = PracticeHub.intent(
            for: .guidedLesson,
            summary: summary(currentLessonTitle: "Past tense"))
        XCTAssertEqual(intent, .lesson(title: "Past tense"))
    }

    func testReviewTileForwardsDueCount() {
        let intent = PracticeHub.intent(
            for: .review,
            summary: summary(dueReviewCount: 7))
        XCTAssertEqual(intent, .review(dueCount: 7))
    }

    // MARK: - Helpers

    private func summary(
        dueReviewCount: Int = 0,
        currentLessonTitle: String? = nil,
        activePlanTitle: String? = nil
    ) -> LearnerProfileSummary {
        LearnerProfileSummary(
            languageName: "French",
            levelName: "A2",
            goalName: "Travel",
            dailyMinutes: 15,
            activePlanTitle: activePlanTitle,
            currentLessonTitle: currentLessonTitle,
            currentLessonStepIndex: nil,
            dueReviewCount: dueReviewCount,
            recentSessionCount: 0,
            minutesPracticedToday: 0
        )
    }
}
