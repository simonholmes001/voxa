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
        let index = abs(variant) % 7

        if snapshot.dueReviewCount > 0 {
            let noun = snapshot.dueReviewCount == 1 ? "review" : "reviews"
            let variants = [
                LearningReminderContent(
                    title: "Your \(language) review is ready",
                    body: "\(snapshot.dueReviewCount) \(noun) are ready in \(language)."),
                LearningReminderContent(
                    title: "Keep \(language) fresh",
                    body: "A quick review of \(snapshot.dueReviewCount) \(noun) keeps them within reach."),
                LearningReminderContent(
                    title: "A little \(language) goes a long way",
                    body: "You have \(snapshot.dueReviewCount) \(noun) waiting for a quick refresh."),
                LearningReminderContent(
                    title: "Your next \(language) win",
                    body: "Clear \(snapshot.dueReviewCount) \(noun) today and keep your recall sharp."),
                LearningReminderContent(
                    title: "Time for a \(language) refresh",
                    body: "\(snapshot.dueReviewCount) \(noun) are ready whenever you have a spare moment."),
                LearningReminderContent(
                    title: "Pick up \(language) again",
                    body: "A short review now will make those \(snapshot.dueReviewCount) \(noun) easier tomorrow."),
                LearningReminderContent(
                    title: "Your \(language) queue is calling",
                    body: "Work through \(snapshot.dueReviewCount) \(noun) in a focused session.")
            ]
            return variants[index]
        }

        if snapshot.minutesPracticedToday >= daily {
            let variants = [
                LearningReminderContent(title: "Nice work in \(language) today", body: "You reached your \(daily)-minute goal. A quick review can lock it in."),
                LearningReminderContent(title: "\(language) goal complete", body: "You put in \(daily) minutes today. Let it settle, then come back tomorrow."),
                LearningReminderContent(title: "You showed up for \(language)", body: "Today’s \(daily)-minute goal is complete. That consistency matters."),
                LearningReminderContent(title: "Keep your \(language) momentum", body: "Your \(daily)-minute goal is done. A small review keeps the words warm."),
                LearningReminderContent(title: "\(language) is moving forward", body: "Another \(daily)-minute goal completed. You’re building the habit."),
                LearningReminderContent(title: "That’s today’s \(language) win", body: "You reached your target. Tomorrow’s progress starts with this habit."),
                LearningReminderContent(title: "Well done in \(language)", body: "Your \(daily)-minute goal is complete. Keep the streak of showing up alive.")
            ]
            return variants[index]
        }

        if snapshot.minutesPracticedToday > 0 {
            let remaining = max(daily - snapshot.minutesPracticedToday, 1)
            let minuteWord = remaining == 1 ? "minute" : "minutes"
            let variants = [
                LearningReminderContent(title: "\(snapshot.minutesPracticedToday) minutes of \(language) logged", body: "Just \(remaining) more \(minuteWord) to reach today’s \(daily)-minute goal."),
                LearningReminderContent(title: "You’re partway through \(language)", body: "You’ve already practiced \(snapshot.minutesPracticedToday) minutes. \(remaining) more \(minuteWord) completes today’s goal."),
                LearningReminderContent(title: "Keep going with \(language)", body: "Your next \(remaining)-minute burst gets you to the \(daily)-minute target."),
                LearningReminderContent(title: "Your \(language) session is underway", body: "You’ve started today. Come back for \(remaining) more \(minuteWord) when you can."),
                LearningReminderContent(title: "Almost at your \(language) goal", body: "\(snapshot.minutesPracticedToday) minutes done; \(remaining) more \(minuteWord) to finish strong."),
                LearningReminderContent(title: "A little more \(language)?", body: "Your progress is waiting at \(snapshot.minutesPracticedToday) minutes today."),
                LearningReminderContent(title: "Build on today’s \(language)", body: "You’ve made a start. One more short session can reach your \(daily)-minute goal.")
            ]
            return variants[index]
        }

        if snapshot.recentSessionCount > 0 {
            let lesson = snapshot.currentLessonTitle
            let focus = lesson.map { " Next up: \($0)." } ?? ""
            let variants = [
                LearningReminderContent(title: "Continue your \(language) momentum", body: "You have practiced recently — a focused \(daily)-minute session keeps it moving.\(focus)"),
                LearningReminderContent(title: "Welcome back to \(language)", body: "Pick up where you left off with a \(daily)-minute session.\(focus)"),
                LearningReminderContent(title: "Your next \(language) session", body: lesson.map { "\($0) is ready when you are." } ?? "A focused session is ready when you are."),
                LearningReminderContent(title: "Keep your \(language) thread", body: "One short session today keeps your recent progress connected.\(focus)"),
                LearningReminderContent(title: "Make today’s \(language) count", body: "You’ve already built momentum. Give it another \(daily)-minute session."),
                LearningReminderContent(title: "A fresh step in \(language)", body: lesson.map { "Continue with \($0) when you have a moment." } ?? "Continue with a focused practice when you have a moment."),
                LearningReminderContent(title: "Don’t lose your \(language) rhythm", body: "A quick session today makes the next one easier.\(focus)")
            ]
            return variants[index]
        }

        if let lesson = snapshot.currentLessonTitle {
            let variants = [
                LearningReminderContent(title: "Ready for \(lesson)", body: "Your \(daily)-minute \(language) goal is ready when you are."),
                LearningReminderContent(title: "Start with \(lesson)", body: "A focused \(language) session is the next step toward your goal."),
                LearningReminderContent(title: "Your next \(language) lesson", body: "\(lesson) is waiting for a first conversation."),
                LearningReminderContent(title: "Make a start in \(language)", body: "Begin \(lesson) with a short session today."),
                LearningReminderContent(title: "A new \(language) step", body: "You can start \(lesson) whenever you have \(daily) minutes."),
                LearningReminderContent(title: "What will you learn next?", body: "Open \(lesson) and make today your first \(language) session."),
                LearningReminderContent(title: "Your \(language) plan is ready", body: "\(lesson) is the next step in your learning plan.")
            ]
            return variants[index]
        }

        let variants = [
            LearningReminderContent(title: "Start your \(language) practice", body: "Your \(daily)-minute goal is ready when you are."),
            LearningReminderContent(title: "A small \(language) session?", body: "A few focused minutes today is enough to keep learning moving."),
            LearningReminderContent(title: "Your \(language) habit starts here", body: "Open voxa for a short session built around your goal."),
            LearningReminderContent(title: "Make a little room for \(language)", body: "A \(daily)-minute session can be the best part of your day."),
            LearningReminderContent(title: "Keep \(language) close", body: "One conversation today gives tomorrow’s words somewhere to land."),
            LearningReminderContent(title: "Ready when you are", body: "Your \(language) practice is set up for a focused start."),
            LearningReminderContent(title: "One step toward \(language)", body: "Start a short session and turn today’s intention into progress.")
        ]
        return variants[index]
    }
}
