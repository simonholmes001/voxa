import XCTest
import VoxaHome
import VoxaOnboarding
import VoxaProfiles
@testable import VoxaAppShell

final class LearningAssistantPlanTests: XCTestCase {
    func testContextPrefersActiveLanguageProfileOverHomeSummary() {
        let context = LearningAssistantPlanFactory.context(
            activeProfile: languageProfile(
                displayName: "German (Germany)",
                goal: "travel",
                minutes: 30,
                level: .a1
            ),
            homeSummary: LearnerProfileSummary(
                languageName: "French",
                levelName: "B1",
                goalName: "Work",
                dailyMinutes: 10
            )
        )

        XCTAssertEqual(context.language, "German")
        XCTAssertEqual(context.level, "A1")
        XCTAssertEqual(context.goal, "Travel")
        XCTAssertEqual(context.dailyMinutes, 30)
    }

    func testContextFallsBackToHomeSummaryWhenNoActiveProfileExists() {
        let context = LearningAssistantPlanFactory.context(
            activeProfile: nil,
            homeSummary: LearnerProfileSummary(
                languageName: "Spanish",
                levelName: "A2",
                goalName: "Family & friends",
                dailyMinutes: 15
            )
        )

        XCTAssertEqual(context.language, "Spanish")
        XCTAssertEqual(context.level, "A2")
        XCTAssertEqual(context.goal, "Family & friends")
        XCTAssertEqual(context.dailyMinutes, 15)
    }

    func testLessonPlanUsesGoalSpecificVoicePractice() {
        let plan = LearningAssistantPlanFactory.makePlan(for: LearningAssistantContext(
            language: "German",
            level: "A1",
            goal: "Travel",
            dailyMinutes: 30
        ))

        XCTAssertEqual(plan.lesson.headline, "Travel German A1")
        XCTAssertEqual(plan.lesson.primaryTitle, "Start voice lesson")
        XCTAssertTrue(plan.lesson.rows.contains {
            $0.id == "key-language" && $0.detail.contains("directions")
        })
        XCTAssertTrue(plan.lesson.rows.contains {
            $0.id == "voice-roleplay" && $0.symbol.contains("mic")
        })
    }

    func testProgressPlanShowsDailyTargetAndReviewLoad() {
        let plan = LearningAssistantPlanFactory.makePlan(for: LearningAssistantContext(
            language: "German",
            level: "A1",
            goal: "Travel",
            dailyMinutes: 30
        ))

        XCTAssertEqual(plan.progress.title, "Progress")
        XCTAssertEqual(plan.progress.primaryTitle, "Continue learning")
        XCTAssertTrue(plan.progress.rows.contains {
            $0.id == "daily-target" && $0.detail.contains("30 minutes")
        })
        XCTAssertTrue(plan.progress.rows.contains { $0.id == "review-load" })
    }

    func testGoalFocusMappingsCoverPrimaryOnboardingGoals() {
        XCTAssertTrue(LearningAssistantPlanFactory.lessonFocus(forDisplayGoal: "Travel").contains("travel"))
        XCTAssertTrue(LearningAssistantPlanFactory.lessonFocus(forDisplayGoal: "Work & career").contains("meetings"))
        XCTAssertTrue(LearningAssistantPlanFactory.lessonFocus(forDisplayGoal: "Family & friends").contains("Everyday"))
        XCTAssertTrue(LearningAssistantPlanFactory.lessonFocus(forDisplayGoal: "Exams").contains("Accuracy"))
        XCTAssertTrue(LearningAssistantPlanFactory.lessonFocus(forDisplayGoal: "Culture & media").contains("Opinions"))
    }

    private func languageProfile(
        displayName: String,
        goal: String,
        minutes: Int,
        level: CEFRLevel
    ) -> LanguageProfile {
        LanguageProfile(
            languageKey: "de-DE",
            displayName: displayName,
            isComplete: true,
            profile: OnboardingProfile(
                targetLanguage: "de-DE",
                nativeLanguage: "en-US",
                goals: [goal],
                minutesPerDay: minutes,
                placementLevel: level
            ),
            version: 1
        )
    }
}
