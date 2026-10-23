#if canImport(UserNotifications)
import Foundation
import UserNotifications
import os

@MainActor
public protocol LearningReminderNotificationCenter {
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

public enum LearningReminderScheduleResult: Equatable, Sendable {
    case scheduled
    case needsProfile
    case failed
}

/// Seven weekly requests keep one varied reminder per day without a seven-day
/// expiry. Updates replace the same identifiers; loading or failure never clears
/// the working schedule.
@MainActor
public enum LearningReminderScheduler {
    public static let identifier = "voxa.daily-learning-reminder"
    private static let logger = Logger(subsystem: "com.simonholmes.voxa", category: "learning-reminders")
    private static var schedulingTask: Task<LearningReminderScheduleResult, Never>?

    public static func schedule(
        snapshot: LearningReminderSnapshot?,
        on center: (any LearningReminderNotificationCenter)? = nil,
        defaults: UserDefaults = .standard
    ) async -> LearningReminderScheduleResult {
        let center = center ?? SystemLearningReminderNotificationCenter()
        // Launch, Home updates and More may request refreshes concurrently.
        // Serialize them so an older snapshot cannot overwrite a newer one.
        let previous = schedulingTask
        let task = Task { @MainActor in
            _ = await previous?.value
            return await update(snapshot: snapshot, on: center, defaults: defaults)
        }
        schedulingTask = task
        return await task.value
    }

    private static func update(
        snapshot: LearningReminderSnapshot?,
        on center: any LearningReminderNotificationCenter,
        defaults: UserDefaults
    ) async -> LearningReminderScheduleResult {
        guard let snapshot = snapshot ?? LearningReminderSnapshotStore.load(defaults: defaults) else {
            return .needsProfile
        }
        LearningReminderSnapshotStore.save(snapshot, defaults: defaults)

        // Recurring copy must not claim that an old day's progress or review
        // counts are still current when the app has not been opened recently.
        let evergreen = LearningReminderSnapshot(
            languageName: snapshot.languageName,
            dailyMinutes: snapshot.dailyMinutes,
            minutesPracticedToday: 0)
        var expected = [UNNotificationRequest]()
        for index in 0..<7 {
            let copy = LearningReminderCopy.content(for: evergreen, variant: index)
            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = .default
            var date = DateComponents()
            date.weekday = index + 1
            date.hour = 18
            date.minute = 0
            expected.append(UNNotificationRequest(
                identifier: "\(identifier)-\(index)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)))
        }

        do {
            for request in expected {
                try await center.add(request)
            }
        } catch {
            logger.error("notification.request.add.failed")
            return .failed
        }

        let pending = await center.pendingNotificationRequests()
        guard expected.allSatisfy({ request in
            pending.contains { candidate in
                guard candidate.identifier == request.identifier,
                      candidate.content.title == request.content.title,
                      candidate.content.body == request.content.body,
                      let trigger = candidate.trigger as? UNCalendarNotificationTrigger,
                      let expectedTrigger = request.trigger as? UNCalendarNotificationTrigger else { return false }
                return trigger.repeats
                    && trigger.dateComponents.weekday == expectedTrigger.dateComponents.weekday
                    && trigger.dateComponents.hour == 18
                    && trigger.dateComponents.minute == 0
                    && trigger.dateComponents.year == nil
                    && trigger.dateComponents.month == nil
                    && trigger.dateComponents.day == nil
            }
        }) else {
            logger.error("notification.schedule.verification.failed")
            return .failed
        }

        // Retire the original generic request only after its replacements have
        // been accepted and verified. The seven dated IDs are replaced in place.
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        return .scheduled
    }
}

@MainActor
private final class SystemLearningReminderNotificationCenter: LearningReminderNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
#endif
