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

    // MARK: - C2 planner-driven Today card

    func testPlanStateReadyPromotesRecommendationOverRuleBasedFallback() {
        // Even when the rule-based fallback would say "review 5 due items",
        // a ready plan wins. This is what turns the Today card from generic
        // rotation into a real per-learner recommendation.
        let plan = LearnerPlan(
            correlationId: "corr",
            recommendedSession: RecommendedSession(
                activityIntent: "pronunciation_drill",
                focusTitle: "French u vowel",
                reason: "you missed the u in *tu* twice last session."),
            focusAreas: ["front rounded vowels", "past-tense forms"])
        let card = PracticeHub.todayCard(
            planState: .ready(plan),
            summary: summary(dueReviewCount: 5))

        // Card title, subtitle, and action all come from the plan.
        XCTAssertEqual(card.title, "Pronunciation drill: French u vowel")
        XCTAssertEqual(card.subtitle, "you missed the u in *tu* twice last session.")
        XCTAssertEqual(card.focusAreas.count, 2)
        XCTAssertEqual(PracticeHub.todayIntent(for: card.recommendation),
                       .pronunciationDrill(focusTitle: "French u vowel"))
    }

    func testPlanStateLoadingFallsBackToRuleBasedRecommendation() {
        // While the plan is loading, don't leave the card blank — the
        // learner sees the rule-based recommendation from B3.
        let card = PracticeHub.todayCard(planState: .loading, summary: summary(dueReviewCount: 3))
        XCTAssertEqual(card.recommendation, .review(dueCount: 3))
    }

    func testPlanStateFailedFallsBackToRuleBasedRecommendation() {
        let card = PracticeHub.todayCard(planState: .failed("boom"), summary: summary(dueReviewCount: 0))
        XCTAssertEqual(card.recommendation, .freeConversation)
    }

    func testPlanRecommendationWithEmptyFocusTitleShowsActivityTitleOnly() {
        // open_practice usually recommends no focus title; the card should
        // display "Speaking practice" rather than "Speaking practice: ".
        let plan = LearnerPlan(
            correlationId: "c",
            recommendedSession: RecommendedSession(
                activityIntent: "open_practice",
                focusTitle: "",
                reason: "let's start with a chat so I can hear you."),
            focusAreas: [])
        let card = PracticeHub.todayCard(planState: .ready(plan), summary: nil)
        XCTAssertEqual(card.title, "Speaking practice")
        XCTAssertEqual(card.focusAreas, [])
    }

    func testPlanRecommendationWithUnknownIntentFallsBackToOpenPracticeIntent() {
        let plan = LearnerPlan(
            correlationId: "c",
            recommendedSession: RecommendedSession(
                activityIntent: "not_a_known_intent",
                focusTitle: "",
                reason: ""),
            focusAreas: [])
        let card = PracticeHub.todayCard(planState: .ready(plan), summary: nil)
        XCTAssertEqual(PracticeHub.todayIntent(for: card.recommendation), .openPractice)
    }

    // MARK: - C3 course-driven Today card

    func testCourseCurrentLessonWinsWhenPlanIsIdle() {
        // The plan is the primary driver (C2). But when it's idle
        // (Practice tab opened before /api/learner/plan resolves), the
        // course arc's current lesson should take over rather than
        // dropping to the pre-C3 title fallback.
        let course = courseWithLessons([
            .completed(title: "Greetings"),
            .current(title: "Cooking verbs", objective: "You'll talk about preparing food."),
        ])
        let card = PracticeHub.todayCard(
            planState: .idle,
            courseState: .ready(course),
            summary: summary(dueReviewCount: 0))
        XCTAssertEqual(card.title, "Today's lesson: Cooking verbs")
        XCTAssertEqual(card.subtitle, "You'll talk about preparing food.")
        XCTAssertEqual(card.actionTitle, "Start lesson")
        XCTAssertEqual(
            PracticeHub.todayIntent(for: card.recommendation),
            .lesson(title: "Cooking verbs"))
    }

    func testPlanStateReadyStillWinsOverCourseCurrentLesson() {
        // Priority order: plan > course > rule-based. The planner sees
        // debrief evidence and may override the arc; that override
        // shouldn't be swallowed by the course lesson.
        let course = courseWithLessons([
            .current(title: "Cooking verbs", objective: "…"),
        ])
        let plan = LearnerPlan(
            correlationId: "p",
            recommendedSession: RecommendedSession(
                activityIntent: "mistakes_replay",
                focusTitle: "past participles",
                reason: "…"),
            focusAreas: [])
        let card = PracticeHub.todayCard(
            planState: .ready(plan),
            courseState: .ready(course),
            summary: nil)
        if case .plan = card.recommendation {
            // OK
        } else {
            XCTFail("expected .plan to win, got \(card.recommendation)")
        }
    }

    func testCourseStateIdleFallsThroughToRuleBasedRecommendation() {
        // Course is loading — the C3 layer shouldn't wedge; the pre-C3
        // rule-based fallback still fires.
        let card = PracticeHub.todayCard(
            planState: .idle,
            courseState: .idle,
            summary: summary(dueReviewCount: 3))
        XCTAssertEqual(card.recommendation, .review(dueCount: 3))
    }

    func testCourseWithNoCurrentLessonFallsThroughToRuleBasedRecommendation() {
        // Fully-completed course + idle plan should NOT surface a
        // ghost lesson tile. Falls back cleanly.
        let course = courseWithLessons([
            .completed(title: "Greetings"),
            .completed(title: "Cooking verbs"),
        ])
        let card = PracticeHub.todayCard(
            planState: .idle,
            courseState: .ready(course),
            summary: summary(dueReviewCount: 0))
        XCTAssertEqual(card.recommendation, .freeConversation)
    }

    // MARK: - Helpers for course-lesson tests

    private enum FakeLessonSpec {
        case completed(title: String)
        case current(title: String, objective: String)
    }

    private func courseWithLessons(_ specs: [FakeLessonSpec]) -> LearnerCourse {
        let lessons: [PlannedLesson] = specs.enumerated().map { pair in
            let (index, spec) = pair
            switch spec {
            case let .completed(title):
                return PlannedLesson(
                    lessonId: "l\(index)",
                    title: title,
                    learningObjective: "",
                    order: index,
                    estimatedMinutes: 15,
                    status: .completed)
            case let .current(title, objective):
                return PlannedLesson(
                    lessonId: "l\(index)",
                    title: title,
                    learningObjective: objective,
                    order: index,
                    estimatedMinutes: 15,
                    status: .current)
            }
        }
        return LearnerCourse(
            correlationId: "c",
            planId: "p",
            title: "Everyday German",
            lessons: lessons)
    }
}
