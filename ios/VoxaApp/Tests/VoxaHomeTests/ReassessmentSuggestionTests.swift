import XCTest
@testable import VoxaHome
import VoxaRealtime

final class ReassessmentSuggestionTests: XCTestCase {

    // MARK: - No suggestion cases

    func testNoSuggestionWhenCourseIsNotReady() {
        let plan = plan(intent: "mistakes_replay")
        XCTAssertEqual(
            ReassessmentSuggestion.evaluate(course: .idle, plan: .ready(plan)),
            .none)
        XCTAssertEqual(
            ReassessmentSuggestion.evaluate(course: .loading, plan: .ready(plan)),
            .none)
        XCTAssertEqual(
            ReassessmentSuggestion.evaluate(course: .failed("boom"), plan: .ready(plan)),
            .none)
    }

    func testNoSuggestionWhenPlanIsNotReady() {
        let course = courseWithCompletedCount(4)
        XCTAssertEqual(
            ReassessmentSuggestion.evaluate(course: .ready(course), plan: .idle),
            .none)
        XCTAssertEqual(
            ReassessmentSuggestion.evaluate(course: .ready(course), plan: .loading),
            .none)
        XCTAssertEqual(
            ReassessmentSuggestion.evaluate(course: .ready(course), plan: .failed("boom")),
            .none)
    }

    func testNoSuggestionWhenLearnerHasNotCompletedEnoughLessons() {
        // Below the threshold the app doesn't have enough evidence yet
        // to suggest a reshape. Default threshold is 3 completed lessons.
        let course = courseWithCompletedCount(2)
        let plan = plan(intent: "mistakes_replay")
        XCTAssertEqual(
            ReassessmentSuggestion.evaluate(course: .ready(course), plan: .ready(plan)),
            .none)
    }

    func testNoSuggestionWhenPlanRecommendsAForwardMotionActivity() {
        // guided_lesson / open_practice / roleplay / etc. are the arc
        // moving forward — no need to reshape.
        let course = courseWithCompletedCount(5)
        for intent in ["guided_lesson", "open_practice", "roleplay", "listening_practice",
                       "vocabulary_drill", "key_language", "review"] {
            XCTAssertEqual(
                ReassessmentSuggestion.evaluate(
                    course: .ready(course),
                    plan: .ready(plan(intent: intent))),
                .none,
                "expected .none for intent \(intent)")
        }
    }

    // MARK: - Suggestion cases

    func testSuggestsReassessmentWhenPlanRecommendsMistakesReplayWithFocus() {
        let course = courseWithCompletedCount(5)
        let plan = plan(intent: "mistakes_replay", focus: "past participles")

        let result = ReassessmentSuggestion.evaluate(
            course: .ready(course),
            plan: .ready(plan))

        guard case let .suggested(_, rationale, hint) = result else {
            return XCTFail("expected .suggested, got \(result)")
        }
        XCTAssertTrue(rationale.contains("past participles"))
        XCTAssertTrue(hint.contains("past participles"))
    }

    func testSuggestsReassessmentWhenPlanRecommendsMistakesReplayWithoutFocus() {
        let course = courseWithCompletedCount(5)
        let plan = plan(intent: "mistakes_replay", focus: "")

        let result = ReassessmentSuggestion.evaluate(
            course: .ready(course),
            plan: .ready(plan))

        guard case let .suggested(_, rationale, hint) = result else {
            return XCTFail("expected .suggested, got \(result)")
        }
        XCTAssertTrue(rationale.contains("recurring"))
        XCTAssertFalse(hint.isEmpty)
    }

    func testSuggestsReassessmentWhenPlanRecommendsPronunciationDrill() {
        let course = courseWithCompletedCount(3)
        let plan = plan(intent: "pronunciation_drill", focus: "French u vowel")

        let result = ReassessmentSuggestion.evaluate(
            course: .ready(course),
            plan: .ready(plan))

        guard case let .suggested(_, rationale, hint) = result else {
            return XCTFail("expected .suggested, got \(result)")
        }
        XCTAssertTrue(rationale.contains("French u vowel"))
        XCTAssertTrue(hint.contains("french u vowel"))
    }

    // MARK: - Helpers

    private func courseWithCompletedCount(_ count: Int) -> LearnerCourse {
        let completed: [PlannedLesson] = (0..<count).map { index in
            PlannedLesson(
                lessonId: "l\(index)",
                title: "Lesson \(index)",
                learningObjective: "…",
                order: index,
                estimatedMinutes: 15,
                status: .completed)
        }
        let current = PlannedLesson(
            lessonId: "current",
            title: "Current",
            learningObjective: "…",
            order: count,
            estimatedMinutes: 15,
            status: .current)
        return LearnerCourse(
            correlationId: "c",
            planId: "p",
            title: "Everyday German",
            lessons: completed + [current])
    }

    private func plan(intent: String, focus: String = "") -> LearnerPlan {
        LearnerPlan(
            correlationId: "p",
            recommendedSession: RecommendedSession(
                activityIntent: intent,
                focusTitle: focus,
                reason: "reason"),
            focusAreas: [])
    }
}
