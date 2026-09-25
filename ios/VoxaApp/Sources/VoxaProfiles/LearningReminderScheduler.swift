#if os(iOS)
import Foundation
import UserNotifications

/// Owns the single notification schedule used by Voxa. Keeping this out of
/// the app entry point prevents an old generic repeating request competing
/// with the personalised requests created from learner progress.
public enum LearningReminderScheduler {
    public static let identifier = "voxa.daily-learning-reminder"

    public static func removeScheduledReminders(from center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers)
    }

    public static func schedule(
        snapshot: LearningReminderSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current,
        on center: UNUserNotificationCenter = .current()
    ) {
        removeScheduledReminders(from: center)
        LearningReminderSnapshotStore.save(snapshot)

        let today = calendar.dateComponents([.year, .month, .day], from: now)
        var todayAtSix = today
        todayAtSix.hour = 18
        todayAtSix.minute = 0
        let firstOffset = calendar.date(from: todayAtSix).map { $0 > now ? 0 : 1 } ?? 1

        for index in 0..<7 {
            let offset = firstOffset + index
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let copy = LearningReminderCopy.content(for: snapshot, variant: index)
            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = .default
            var date = calendar.dateComponents([.year, .month, .day], from: day)
            date.hour = 18
            date.minute = 0
            center.add(UNNotificationRequest(
                identifier: "\(identifier)-\(index)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
            ))
        }
    }

    private static let allIdentifiers = [identifier] + (0..<7).map { "\(identifier)-\($0)" }
}
#endif
