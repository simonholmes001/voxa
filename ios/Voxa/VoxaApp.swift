import SwiftUI
#if os(iOS)
import UserNotifications
#endif

/// The Voxa iPhone and iPad application entry point.
///
/// The entry point is intentionally thin: it hosts the adaptive root view
/// provided by `AppComposition`, which the app shell renders as a tab bar on
/// compact width (iPhone) or a split view on regular width (iPad).
@main
struct VoxaApp: App {
    /// Build the composition (auth, onboarding, profile, talk, home view models)
    /// exactly once. `makeRootView()` is a factory that instantiates fresh view
    /// models on every call, so it must never run inside the `WindowGroup`
    /// content closure — SwiftUI re-evaluates that closure on re-render, which
    /// would rewire `RootView`'s non-`@State` child models (e.g. `profileModel`)
    /// to a brand-new, signed-out `AuthViewModel` while the sticky `@State`
    /// `authModel` behind the auth gate stays signed in. That split is what left
    /// authenticated requests with no access token. Holding the composed root in
    /// `@State` pins a single, consistent set of models for the app's lifetime.
    @State private var root = AppComposition.makeRootView()
    @State private var showNotificationPrimer = false
    @State private var showNotificationDeniedFollowUp = false
    @AppStorage("voxa.learningNotifications.prompted") private var hasPromptedForLearningNotifications = false

    var body: some Scene {
        WindowGroup {
            root
                #if os(iOS)
                .task { await prepareLearningNotifications() }
                .alert("Daily learning reminder?", isPresented: $showNotificationPrimer) {
                    Button("Not now", role: .cancel) {
                        hasPromptedForLearningNotifications = true
                        showNotificationDeniedFollowUp = true
                    }
                    Button("Allow reminders") {
                        Task { await requestLearningNotifications() }
                    }
                } message: {
                    Text("Voxa can send one daily reminder about your language progress and invite you to continue learning.")
                }
                .alert("Reminders are off", isPresented: $showNotificationDeniedFollowUp) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("You will not receive daily progress reminders. You can turn them on later from More.")
                }
                #endif
        }
    }

    #if os(iOS)
    @MainActor
    private func prepareLearningNotifications() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            scheduleDailyLearningReminder()
        case .notDetermined where !hasPromptedForLearningNotifications:
            try? await Task.sleep(nanoseconds: 900_000_000)
            showNotificationPrimer = true
        default:
            break
        }
    }

    @MainActor
    private func requestLearningNotifications() async {
        hasPromptedForLearningNotifications = true
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            if granted {
                scheduleDailyLearningReminder()
            } else {
                showNotificationDeniedFollowUp = true
            }
        } catch {
            showNotificationDeniedFollowUp = true
        }
    }

    private func scheduleDailyLearningReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyLearningReminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Keep your language progress moving"
        content.body = "A short Voxa session today helps your new language stick."
        content.sound = .default

        var date = DateComponents()
        date.hour = 18
        date.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.dailyLearningReminderIdentifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    private static let dailyLearningReminderIdentifier = "voxa.daily-learning-reminder"
    #endif
}
