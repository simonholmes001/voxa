#if canImport(SwiftUI)
import Foundation
import VoxaHome
import VoxaOnboarding
import VoxaProfiles

struct LearningAssistantContext: Equatable {
    let language: String
    let level: String
    let goal: String
    let dailyMinutes: Int
    let activePlanTitle: String?
    let currentLessonTitle: String?
    let currentLessonStepIndex: Int?
    let dueReviewCount: Int
    let recentSessionCount: Int
    let minutesPracticedToday: Int

    init(
        language: String,
        level: String,
        goal: String,
        dailyMinutes: Int,
        activePlanTitle: String? = nil,
        currentLessonTitle: String? = nil,
        currentLessonStepIndex: Int? = nil,
        dueReviewCount: Int = 0,
        recentSessionCount: Int = 0,
        minutesPracticedToday: Int = 0
    ) {
        self.language = language
        self.level = level
        self.goal = goal
        self.dailyMinutes = dailyMinutes
        self.activePlanTitle = activePlanTitle
        self.currentLessonTitle = currentLessonTitle
        self.currentLessonStepIndex = currentLessonStepIndex
        self.dueReviewCount = dueReviewCount
        self.recentSessionCount = recentSessionCount
        self.minutesPracticedToday = minutesPracticedToday
    }
}

struct LearningAssistantPlan: Equatable {
    let lesson: LearningRouteContent
    let review: LearningRouteContent
    let progress: LearningRouteContent
    let settings: LearningRouteContent
}

struct LearningRouteContent: Equatable {
    let title: String
    let symbol: String
    let headline: String
    let detail: String
    let primaryTitle: String
    let primarySymbol: String
    let rows: [LearningRouteRow]
}

struct LearningRouteRow: Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
}

enum LearningAssistantPlanFactory {
    static func context(
        activeProfile: LanguageProfile?,
        homeSummary: LearnerProfileSummary?
    ) -> LearningAssistantContext {
        if let activeProfile {
            return LearningAssistantContext(
                language: shortLanguageName(activeProfile.displayName),
                level: activeProfile.profile.placementLevel.displayName,
                goal: activeProfile.profile.goals.first.map(GoalSelection.displayTitle(for:)) ?? "Daily",
                dailyMinutes: activeProfile.profile.minutesPerDay,
                activePlanTitle: homeSummary?.activePlanTitle,
                currentLessonTitle: homeSummary?.currentLessonTitle,
                currentLessonStepIndex: homeSummary?.currentLessonStepIndex,
                dueReviewCount: homeSummary?.dueReviewCount ?? 0,
                recentSessionCount: homeSummary?.recentSessionCount ?? 0,
                minutesPracticedToday: homeSummary?.minutesPracticedToday ?? 0
            )
        }

        if let homeSummary {
            return LearningAssistantContext(
                language: homeSummary.languageName,
                level: homeSummary.levelName,
                goal: homeSummary.goalName,
                dailyMinutes: homeSummary.dailyMinutes,
                activePlanTitle: homeSummary.activePlanTitle,
                currentLessonTitle: homeSummary.currentLessonTitle,
                currentLessonStepIndex: homeSummary.currentLessonStepIndex,
                dueReviewCount: homeSummary.dueReviewCount,
                recentSessionCount: homeSummary.recentSessionCount,
                minutesPracticedToday: homeSummary.minutesPracticedToday
            )
        }

        return LearningAssistantContext(
            language: "language",
            level: "A1",
            goal: "Daily",
            dailyMinutes: 15,
            activePlanTitle: nil,
            currentLessonTitle: nil,
            currentLessonStepIndex: nil,
            dueReviewCount: 0,
            recentSessionCount: 0,
            minutesPracticedToday: 0
        )
    }

    static func makePlan(for context: LearningAssistantContext) -> LearningAssistantPlan {
        LearningAssistantPlan(
            lesson: lessonContent(for: context),
            review: reviewContent(for: context),
            progress: progressContent(for: context),
            settings: settingsContent()
        )
    }

    static func lessonFocus(forDisplayGoal goal: String) -> String {
        switch goal.lowercased() {
        case let value where value.contains("travel"):
            return "Getting around, booking, directions, and useful travel repairs"
        case let value where value.contains("work"):
            return "Introductions, meetings, polite requests, and workplace small talk"
        case let value where value.contains("family") || value.contains("friend"):
            return "Everyday catch-ups, invitations, preferences, and personal stories"
        case let value where value.contains("exam"):
            return "Accuracy drills, structured answers, and timed speaking prompts"
        case let value where value.contains("culture") || value.contains("media"):
            return "Opinions, recommendations, summaries, and natural reactions"
        default:
            return "Useful phrases for your next real conversation"
        }
    }

    static func shortLanguageName(_ displayName: String) -> String {
        displayName.replacingOccurrences(
            of: #"\s*\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func lessonContent(for context: LearningAssistantContext) -> LearningRouteContent {
        LearningRouteContent(
            title: "Today's lesson",
            symbol: "book.closed",
            headline: context.activePlanTitle ?? "\(context.goal) \(context.language) \(context.level)",
            detail: "A short assistant-led lesson: warm up, learn useful phrases, then practise aloud in a realistic scenario.",
            primaryTitle: "Start voice lesson",
            primarySymbol: "mic.fill",
            rows: [
                LearningRouteRow(
                    id: "briefing",
                    title: "Tutor briefing",
                    detail: lessonBriefing(for: context),
                    symbol: "sparkles"
                ),
                LearningRouteRow(
                    id: "key-language",
                    title: "Key language",
                    detail: lessonFocus(forDisplayGoal: context.goal),
                    symbol: "book.closed"
                ),
                LearningRouteRow(
                    id: "voice-roleplay",
                    title: "Voice roleplay",
                    detail: "Answer naturally, get corrected, and try again",
                    symbol: "mic.circle"
                )
            ]
        )
    }

    private static func reviewContent(for context: LearningAssistantContext) -> LearningRouteContent {
        LearningRouteContent(
            title: "Review",
            symbol: "arrow.triangle.2.circlepath",
            headline: "Strengthen your \(context.language)",
            detail: "Voxa should turn each tutor session into focused review: mistakes, unstable words, and pronunciation targets.",
            primaryTitle: "Review with tutor",
            primarySymbol: "mic.fill",
            rows: [
                LearningRouteRow(
                    id: "recent-mistakes",
                    title: "Recent mistakes",
                    detail: reviewLoadDetail(for: context),
                    symbol: "exclamationmark.bubble"
                ),
                LearningRouteRow(
                    id: "words-due",
                    title: "Words due",
                    detail: "Spaced repetition for unstable vocabulary",
                    symbol: "textformat.abc"
                ),
                LearningRouteRow(
                    id: "pronunciation",
                    title: "Pronunciation",
                    detail: "Minimal-pair drills for sounds you miss",
                    symbol: "waveform"
                )
            ]
        )
    }

    private static func progressContent(for context: LearningAssistantContext) -> LearningRouteContent {
        LearningRouteContent(
            title: "Progress",
            symbol: "chart.bar",
            headline: "\(context.language) is in motion",
            detail: "Track the habits and signals that matter for a voice-first tutor: minutes, lesson progress, review load, and confidence.",
            primaryTitle: "Continue learning",
            primarySymbol: "play.fill",
            rows: [
                LearningRouteRow(
                    id: "daily-target",
                    title: "Daily target",
                    detail: "\(context.minutesPracticedToday) of \(context.dailyMinutes) minutes completed for \(context.level)",
                    symbol: "clock"
                ),
                LearningRouteRow(
                    id: "lesson-path",
                    title: "Lesson path",
                    detail: "Current focus: \(lessonFocus(forDisplayGoal: context.goal))",
                    symbol: "list.bullet.rectangle"
                ),
                LearningRouteRow(
                    id: "review-load",
                    title: "Review load",
                    detail: reviewLoadDetail(for: context),
                    symbol: "tray.full"
                )
            ]
        )
    }

    private static func settingsContent() -> LearningRouteContent {
        LearningRouteContent(
            title: "Settings",
            symbol: "person.crop.circle",
            headline: "Manage your tutor",
            detail: "Language profiles, daily time, goals, and account settings live here.",
            primaryTitle: "Add a language",
            primarySymbol: "plus.circle",
            rows: [
                LearningRouteRow(
                    id: "languages",
                    title: "Languages",
                    detail: "Switch between the languages you are learning",
                    symbol: "globe"
                ),
                LearningRouteRow(
                    id: "goals",
                    title: "Goals",
                    detail: "Tune what your tutor should optimize for",
                    symbol: "target"
                ),
                LearningRouteRow(
                    id: "session-style",
                    title: "Session style",
                    detail: "Control how much correction and explanation you want",
                    symbol: "slider.horizontal.3"
                )
            ]
        )
    }

    private static func lessonBriefing(for context: LearningAssistantContext) -> String {
        if let lesson = context.currentLessonTitle {
            let step = context.currentLessonStepIndex.map { ", step \($0 + 1)" } ?? ""
            return "Continue \(lesson)\(step) in a \(context.dailyMinutes)-minute session"
        }
        return "\(context.dailyMinutes) minutes focused on what you can use today"
    }

    private static func reviewLoadDetail(for context: LearningAssistantContext) -> String {
        if context.dueReviewCount > 0 {
            return "\(context.dueReviewCount) due from recent tutor sessions"
        }
        if context.recentSessionCount > 0 {
            return "No due items yet from \(context.recentSessionCount) recent sessions"
        }
        return "Start a tutor session to create mistake and word review"
    }
}
#endif
