import Foundation
import VoxaRealtime

/// Pure model + logic for the Practice tab. Deliberately no SwiftUI here so the
/// tile-visibility rules and "Today" recommendation logic are unit-testable
/// without a rendered view or a device.
public enum PracticeHub {

    // MARK: - Today card

    /// One recommended session for the current moment. Prefers the C2
    /// backend planner's LearnerPlan when it's `.ready`; otherwise falls
    /// back to the rule-based recommendation (due reviews > continue
    /// lesson > free conversation) shipped in B3. The learner never sees
    /// a blank card because of a network hiccup.
    public static func todayCard(
        planState: LearnerPlanState = .idle,
        summary: LearnerProfileSummary?
    ) -> PracticeHubTodayCard {
        if case let .ready(plan) = planState {
            return PracticeHubTodayCard(recommendation: .plan(plan))
        }
        return ruleBasedTodayCard(for: summary)
    }

    /// Back-compat overload for the pre-planner call sites — same shape as
    /// C1 and earlier so tests and views not yet migrated keep compiling.
    public static func todayCard(for summary: LearnerProfileSummary?) -> PracticeHubTodayCard {
        return ruleBasedTodayCard(for: summary)
    }

    private static func ruleBasedTodayCard(for summary: LearnerProfileSummary?) -> PracticeHubTodayCard {
        if let summary, summary.dueReviewCount > 0 {
            return PracticeHubTodayCard(recommendation: .review(dueCount: summary.dueReviewCount))
        }
        if let title = nonEmpty(summary?.currentLessonTitle) ?? nonEmpty(summary?.activePlanTitle) {
            return PracticeHubTodayCard(recommendation: .continueLesson(title: title))
        }
        return PracticeHubTodayCard(recommendation: .freeConversation)
    }

    /// Resolves the Today card's recommendation into a `RealtimeTutorIntent`
    /// that the Talk model can start.
    public static func todayIntent(for recommendation: PracticeHubTodayCard.Recommendation) -> RealtimeTutorIntent {
        switch recommendation {
        case let .review(dueCount):
            return .review(dueCount: dueCount)
        case let .continueLesson(title):
            return .lesson(title: title)
        case .freeConversation:
            return .openPractice
        case let .plan(plan):
            // Use the same snake_case → intent mapping the debrief
            // recommendation does; unknown intents fall back safely.
            return plan.recommendedSession.intent
        }
    }

    // MARK: - Tile grid

    /// The tiles the Practice tab shows. Some (guidedLesson, keyLanguage) only
    /// appear when the learner has enough context to launch them meaningfully;
    /// hiding them beats surfacing a tile that would launch with placeholder
    /// content.
    public static func tiles(for summary: LearnerProfileSummary?) -> [PracticeHubTile] {
        var tiles: [PracticeHubTile] = [
            PracticeHubTile(kind: .freeConversation),
            PracticeHubTile(kind: .fixRecentMistakes),
            PracticeHubTile(kind: .pronunciation),
            PracticeHubTile(kind: .listening),
            PracticeHubTile(kind: .vocabulary),
            PracticeHubTile(kind: .roleplay),
        ]
        if nonEmpty(summary?.activePlanTitle) != nil || nonEmpty(summary?.currentLessonTitle) != nil {
            tiles.append(PracticeHubTile(kind: .guidedLesson))
        }
        if nonEmpty(summary?.currentLessonTitle) != nil {
            tiles.append(PracticeHubTile(kind: .keyLanguage))
        }
        tiles.append(PracticeHubTile(kind: .review))
        return tiles
    }

    /// Resolves a tile tap into a `RealtimeTutorIntent`. Tiles that carry
    /// activity-specific context (roleplay scenario, key-language topic,
    /// guided-lesson title, review due-count) receive it here rather than
    /// baking it into the tile struct.
    public static func intent(
        for kind: PracticeHubTile.Kind,
        summary: LearnerProfileSummary?
    ) -> RealtimeTutorIntent {
        switch kind {
        case .freeConversation:
            return .openPractice
        case .fixRecentMistakes:
            return .mistakesReplay()
        case .pronunciation:
            return .pronunciationDrill()
        case .listening:
            return .listeningPractice()
        case .vocabulary:
            return .vocabularyDrill()
        case .roleplay:
            // Placeholder scenario until B4 ships a scenario library.
            return .roleplay(scenarioTitle: "An everyday café order")
        case .keyLanguage:
            let topic = nonEmpty(summary?.currentLessonTitle)
                ?? nonEmpty(summary?.activePlanTitle)
                ?? "the language coming up next"
            return .keyLanguage(topic: topic)
        case .guidedLesson:
            return .lesson(title: nonEmpty(summary?.currentLessonTitle) ?? nonEmpty(summary?.activePlanTitle))
        case .review:
            return .review(dueCount: summary?.dueReviewCount ?? 0)
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Today card

public struct PracticeHubTodayCard: Sendable, Equatable {
    public enum Recommendation: Sendable, Equatable {
        case review(dueCount: Int)
        case continueLesson(title: String)
        case freeConversation
        /// C2 planner-driven recommendation. When present, its title and
        /// subtitle come from the plan itself so the learner sees a
        /// concrete pattern name and a per-session reason instead of the
        /// generic rule-based labels.
        case plan(LearnerPlan)
    }

    public let recommendation: Recommendation

    public init(recommendation: Recommendation) {
        self.recommendation = recommendation
    }

    public var title: String {
        switch recommendation {
        case let .review(dueCount):
            return dueCount == 1 ? "Review 1 due item" : "Review \(dueCount) due items"
        case let .continueLesson(title):
            return "Continue: \(title)"
        case .freeConversation:
            return "Start speaking"
        case let .plan(plan):
            let focus = plan.recommendedSession.focusTitle
            if !focus.isEmpty {
                return "\(plan.recommendedSession.intent.title): \(focus)"
            }
            return plan.recommendedSession.intent.title
        }
    }

    public var subtitle: String {
        switch recommendation {
        case .review:
            return "Pick up where the tutor last flagged your weakest points."
        case .continueLesson:
            return "Keep going with today's lesson while it's fresh."
        case .freeConversation:
            return "Open-ended practice with the tutor — you drive the topic."
        case let .plan(plan):
            let reason = plan.recommendedSession.reason
            return reason.isEmpty
                ? "Recommended based on your recent sessions."
                : reason
        }
    }

    public var actionTitle: String {
        switch recommendation {
        case .review: return "Start review"
        case .continueLesson: return "Continue lesson"
        case .freeConversation: return "Start talking"
        case let .plan(plan): return plan.recommendedSession.intent.startButtonTitle
        }
    }

    /// Up to three concrete focus areas the C2 planner surfaced with the
    /// recommendation. Rendered as chips on the Home Today card.
    public var focusAreas: [String] {
        if case let .plan(plan) = recommendation { return plan.focusAreas }
        return []
    }
}

// MARK: - Tile

public struct PracticeHubTile: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case freeConversation
        case fixRecentMistakes
        case pronunciation
        case listening
        case vocabulary
        case roleplay
        case keyLanguage
        case guidedLesson
        case review
    }

    public let kind: Kind

    public var id: String { kind.rawValue }

    public init(kind: Kind) {
        self.kind = kind
    }

    public var title: String {
        switch kind {
        case .freeConversation: return "Free conversation"
        case .fixRecentMistakes: return "Fix recent mistakes"
        case .pronunciation: return "Pronunciation"
        case .listening: return "Listening"
        case .vocabulary: return "Vocabulary"
        case .roleplay: return "Roleplay"
        case .keyLanguage: return "Key language brief"
        case .guidedLesson: return "Guided lesson"
        case .review: return "Review"
        }
    }

    public var subtitle: String {
        switch kind {
        case .freeConversation: return "You drive the topic. The tutor follows and gently corrects."
        case .fixRecentMistakes: return "Target the errors that keep coming back across sessions."
        case .pronunciation: return "Minimal-pair drills with specific articulatory feedback."
        case .listening: return "Tutor speaks; you show you understood."
        case .vocabulary: return "A small themed word set, used and re-used until it sticks."
        case .roleplay: return "A real-world scenario. Tutor stays in character."
        case .keyLanguage: return "A quick brief on structures coming up next."
        case .guidedLesson: return "Warm-up → target → practice → correction → retry."
        case .review: return "Prompt the due items first, then explain."
        }
    }

    public var symbol: String {
        switch kind {
        case .freeConversation: return "text.bubble"
        case .fixRecentMistakes: return "wrench.and.screwdriver"
        case .pronunciation: return "waveform.badge.mic"
        case .listening: return "ear"
        case .vocabulary: return "textformat.abc"
        case .roleplay: return "theatermasks"
        case .keyLanguage: return "sparkles"
        case .guidedLesson: return "book.pages"
        case .review: return "arrow.triangle.2.circlepath"
        }
    }
}
