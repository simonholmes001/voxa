import Foundation

/// The small, locally available slice of learner progress used to make a
/// reminder useful without putting learner data in a remote notification.
public struct LearningReminderSnapshot: Sendable, Equatable, Codable {
    public let languageName: String
    public let dailyMinutes: Int
    public let minutesPracticedToday: Int
    public let dueReviewCount: Int
    public let recentSessionCount: Int
    public let currentLessonTitle: String?

    public init(
        languageName: String,
        dailyMinutes: Int,
        minutesPracticedToday: Int,
        dueReviewCount: Int = 0,
        recentSessionCount: Int = 0,
        currentLessonTitle: String? = nil
    ) {
        self.languageName = languageName
        self.dailyMinutes = dailyMinutes
        self.minutesPracticedToday = minutesPracticedToday
        self.dueReviewCount = dueReviewCount
        self.recentSessionCount = recentSessionCount
        self.currentLessonTitle = currentLessonTitle
    }
}

/// Persists the last learner snapshot used to schedule reminders. This lets
/// the app refresh notification requests on launch without making a network
/// request or falling back to generic copy.
public enum LearningReminderSnapshotStore {
    public static let key = "voxa.learningNotifications.snapshot"

    public static func save(_ snapshot: LearningReminderSnapshot, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    public static func load(defaults: UserDefaults = .standard) -> LearningReminderSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LearningReminderSnapshot.self, from: data)
    }
}

public struct LearningReminderContent: Sendable, Equatable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// Deterministic copy so scheduled reminders reflect the learner's actual
/// state and can be covered by unit tests.
public enum LearningReminderCopy {
    public static func content(
        for snapshot: LearningReminderSnapshot,
        variant: Int = 0
    ) -> LearningReminderContent {
        let language = snapshot.languageName
        let daily = max(snapshot.dailyMinutes, 1)

        if snapshot.dueReviewCount > 0 {
            let noun = snapshot.dueReviewCount == 1 ? "review" : "reviews"
            let variants = [
                "\(snapshot.dueReviewCount) \(noun) are ready in \(language).",
                "Keep \(language) fresh with \(snapshot.dueReviewCount) quick \(noun)."
            ]
            return LearningReminderContent(
                title: "Your \(language) review is ready",
                body: variants[abs(variant) % variants.count]
            )
        }

        if snapshot.minutesPracticedToday >= daily {
            return LearningReminderContent(
                title: "Nice work in \(language) today",
                body: variant.isMultiple(of: 2)
                    ? "You reached your \(daily)-minute goal. A quick review can lock it in."
                    : "Your \(daily)-minute goal is complete. Keep the momentum going tomorrow."
            )
        }

        if snapshot.minutesPracticedToday > 0 {
            let remaining = max(daily - snapshot.minutesPracticedToday, 1)
            return LearningReminderContent(
                title: "\(snapshot.minutesPracticedToday) minutes of \(language) logged",
                body: "Just \(remaining) more minute\(remaining == 1 ? "" : "s") to reach today's \(daily)-minute goal."
            )
        }

        if snapshot.recentSessionCount > 0 {
            let focus = snapshot.currentLessonTitle.map { " Continue \($0) next." } ?? ""
            return LearningReminderContent(
                title: "Continue your \(language) momentum",
                body: variant.isMultiple(of: 2)
                    ? "You have practiced recently — a focused \(daily)-minute session keeps it moving.\(focus)"
                    : "Pick up \(language) where you left off with a \(daily)-minute session.\(focus)"
            )
        }

        return LearningReminderContent(
            title: "Start your \(language) practice",
            body: variant.isMultiple(of: 2)
                ? "Your \(daily)-minute goal is ready when you are."
                : "A short \(language) session is the next step toward your goal."
        )
    }
}
