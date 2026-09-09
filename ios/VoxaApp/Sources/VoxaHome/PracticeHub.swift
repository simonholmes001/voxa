import Foundation
import VoxaRealtime

/// Pure model + logic for the Practice tab. Deliberately no SwiftUI here so the
/// tile-visibility rules and "Today" recommendation logic are unit-testable
/// without a rendered view or a device.
public enum PracticeHub {

    // MARK: - Today card

    /// One recommended session for the current moment. MVP logic is rule-based
    /// (due reviews > continue lesson > free conversation); the learner-model
    /// version lands in Phase C.
    public static func todayCard(for summary: LearnerProfileSummary?) -> PracticeHubTodayCard {
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
        }
    }

    public var actionTitle: String {
        switch recommendation {
        case .review: return "Start review"
        case .continueLesson: return "Continue lesson"
        case .freeConversation: return "Start talking"
        }
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
