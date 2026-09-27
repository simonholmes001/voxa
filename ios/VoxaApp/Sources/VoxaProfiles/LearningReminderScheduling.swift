import Foundation

/// Keeps the launch-time reminder decision independent from UserNotifications
/// so the authorized-user path can be regression tested without an iOS runtime.
public enum LearningReminderScheduling {
    public static func shouldSchedule(
        snapshot: LearningReminderSnapshot?,
        notificationsAuthorized: Bool
    ) -> Bool {
        notificationsAuthorized && snapshot != nil
    }
}
