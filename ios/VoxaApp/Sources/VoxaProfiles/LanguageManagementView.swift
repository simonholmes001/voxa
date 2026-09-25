#if canImport(SwiftUI)
import SwiftUI
#if os(iOS)
import UIKit
import UserNotifications
#endif

/// In-app language manager hosted by the More surface.
///
/// Lets the learner run several courses in parallel: see every language
/// profile, switch the active one, add a new language, edit a language's
/// settings, and sign out. It reads the profile list supplied by
/// `ProfileSelectionViewModel` and edits each language through a
/// `LanguageSettingsViewModel`, so one language's progress can never overwrite
/// another's (the backend enforces per-language idempotency by target language).
public struct LanguageManagementView: View {
    private let profiles: [LanguageProfile]
    private let activeKey: String?
    private let makeSettingsModel: @MainActor (LanguageProfile) -> LanguageSettingsViewModel
    private let onSwitch: (LanguageProfile) -> Void
    private let onAddLanguage: () -> Void
    private let onSaved: () async -> Void
    private let onDelete: (LanguageProfile) async -> Bool
    private let privacyPolicyURL: URL?
    private let onExportAccountData: () async throws -> URL
    private let onDeleteAccount: () async throws -> Void
    private let onSignOut: () -> Void
    private let reminderSnapshot: LearningReminderSnapshot?
    private let progressDestination: AnyView?
    private let showsMoreDestinations: Bool
    private let navigationTitle: String
    @Environment(\.openURL) private var openURL
    @State private var editingProfile: LanguageProfile?
    @State private var profileToDelete: LanguageProfile?
    @State private var exportedAccountDataURL: URL?
    @State private var accountDataMessage: String?
    @State private var accountDataError: String?
    @State private var isExportingAccountData = false
    @State private var isDeletingAccount = false
    @State private var confirmAccountDeletion = false

    public init(
        profiles: [LanguageProfile],
        activeKey: String?,
        makeSettingsModel: @escaping @MainActor (LanguageProfile) -> LanguageSettingsViewModel,
        onSwitch: @escaping (LanguageProfile) -> Void,
        onAddLanguage: @escaping () -> Void,
        onSaved: @escaping () async -> Void,
        onDelete: @escaping (LanguageProfile) async -> Bool = { _ in false },
        privacyPolicyURL: URL? = nil,
        onExportAccountData: @escaping () async throws -> URL = {
            throw AccountDataActionError.unavailable
        },
        onDeleteAccount: @escaping () async throws -> Void = {
            throw AccountDataActionError.unavailable
        },
        onSignOut: @escaping () -> Void,
        reminderSnapshot: LearningReminderSnapshot? = nil,
        progressDestination: AnyView? = nil,
        showsMoreDestinations: Bool = false,
        navigationTitle: String = "Languages"
    ) {
        self.profiles = profiles
        self.activeKey = activeKey
        self.makeSettingsModel = makeSettingsModel
        self.onSwitch = onSwitch
        self.onAddLanguage = onAddLanguage
        self.onSaved = onSaved
        self.onDelete = onDelete
        self.privacyPolicyURL = privacyPolicyURL
        self.onExportAccountData = onExportAccountData
        self.onDeleteAccount = onDeleteAccount
        self.onSignOut = onSignOut
        self.reminderSnapshot = reminderSnapshot
        self.progressDestination = progressDestination
        self.showsMoreDestinations = showsMoreDestinations
        self.navigationTitle = navigationTitle
    }

    public var body: some View {
        List {
            Section {
                NavigationLink {
                    TutorSetupView(
                        profiles: profiles,
                        activeKey: activeKey,
                        makeSettingsModel: makeSettingsModel,
                        onSaved: onSaved
                    )
                } label: {
                    Label("Tutor setup", systemImage: "person.wave.2")
                }
                .accessibilityIdentifier("language-manager-tutor-setup")

                if showsMoreDestinations, let progressDestination {
                    NavigationLink {
                        progressDestination
                    } label: {
                        Label("Progress", systemImage: "chart.bar")
                    }
                    .accessibilityIdentifier("language-manager-progress")
                }

                if showsMoreDestinations {
                    NavigationLink {
                        LanguageManagementView(
                            profiles: profiles,
                            activeKey: activeKey,
                            makeSettingsModel: makeSettingsModel,
                            onSwitch: onSwitch,
                            onAddLanguage: onAddLanguage,
                            onSaved: onSaved,
                            onDelete: onDelete,
                            privacyPolicyURL: privacyPolicyURL,
                            onExportAccountData: onExportAccountData,
                            onDeleteAccount: onDeleteAccount,
                            onSignOut: onSignOut,
                            navigationTitle: "Settings"
                        )
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("language-manager-settings")
                }
            } footer: {
                Text("Languages, goals, daily time, and correction style shape how voxa teaches you.")
            }

            Section("Your languages") {
                if profiles.isEmpty {
                    Text("You don't have any languages yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        Button {
                            editingProfile = profile
                        } label: {
                            LanguageRow(profile: profile, isActive: profile.languageKey == activeKey)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                profileToDelete = profile
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section {
                Button(action: onAddLanguage) {
                    Label("Add a language", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("language-manager-add")
            } footer: {
                Text("Start another course. Your other languages keep their own progress.")
            }

            #if os(iOS)
            DailyLearningReminderSection(snapshot: reminderSnapshot)
            #endif

            Section {
                if let accountDataMessage {
                    Text(accountDataMessage)
                        .foregroundStyle(.secondary)
                }
                if let accountDataError {
                    Text(accountDataError)
                        .foregroundStyle(.red)
                }
                Button {
                    if let privacyPolicyURL {
                        openURL(privacyPolicyURL)
                    }
                } label: {
                    Label("Privacy policy", systemImage: "hand.raised")
                }
                .disabled(privacyPolicyURL == nil)
                .accessibilityIdentifier("language-manager-privacy-policy")

                Button {
                    Task { await exportAccountData() }
                } label: {
                    if isExportingAccountData {
                        ProgressView()
                    } else {
                        Label("Export my data", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isExportingAccountData)
                .accessibilityIdentifier("language-manager-export-data")

                if let exportedAccountDataURL {
                    ShareLink(item: exportedAccountDataURL) {
                        Label("Share exported file", systemImage: "doc")
                    }
                    .accessibilityIdentifier("language-manager-share-export")
                }

                Button(role: .destructive) {
                    confirmAccountDeletion = true
                } label: {
                    if isDeletingAccount {
                        ProgressView()
                    } else {
                        Label("Delete account", systemImage: "trash")
                    }
                }
                .disabled(isDeletingAccount)
                .accessibilityIdentifier("language-manager-delete-account")
            } header: {
                Text("Privacy & data")
            } footer: {
                Text("Export includes your stored Voxa learner data. Account deletion removes your Voxa account data and signs you out.")
            }

            Section {
                Button(role: .destructive, action: onSignOut) {
                    Text("Sign out")
                }
                .accessibilityIdentifier("language-manager-sign-out")
            }
        }
        .navigationTitle(navigationTitle)
        .confirmationDialog(
            "Delete your Voxa account?",
            isPresented: $confirmAccountDeletion
        ) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your Voxa learner data and signs you out. This action cannot be undone.")
        }
        .confirmationDialog(
            "Delete \(profileToDelete?.displayName ?? "language")?",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            presenting: profileToDelete
        ) { profile in
            Button("Delete", role: .destructive) {
                Task {
                    if await onDelete(profile) { await onSaved() }
                    profileToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { profileToDelete = nil }
        } message: { profile in
            Text("This removes your progress for \(profile.displayName.asLanguageDisplayName).")
        }
        .sheet(item: $editingProfile) { profile in
            NavigationStack {
                LanguageDetailView(
                    profile: profile,
                    isActive: profile.languageKey == activeKey,
                    makeSettingsModel: makeSettingsModel,
                    onSwitch: { onSwitch(profile) },
                    onSaved: onSaved
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { editingProfile = nil }
                    }
                }
            }
        }
    }

    private func exportAccountData() async {
        isExportingAccountData = true
        accountDataError = nil
        accountDataMessage = nil
        do {
            exportedAccountDataURL = try await onExportAccountData()
            accountDataMessage = "Your export is ready."
        } catch {
            accountDataError = message(for: error)
        }
        isExportingAccountData = false
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        accountDataError = nil
        accountDataMessage = nil
        do {
            try await onDeleteAccount()
        } catch {
            accountDataError = message(for: error)
            isDeletingAccount = false
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case AccountDataActionError.unavailable:
            return "Privacy controls are not configured for this build."
        default:
            return "The account data request failed. Please try again."
        }
    }
}

public enum AccountDataActionError: Error, Equatable {
    case unavailable
}

#if os(iOS)
private struct DailyLearningReminderSection: View {
    let snapshot: LearningReminderSnapshot?
    @Environment(\.openURL) private var openURL
    @AppStorage("voxa.learningNotifications.prompted") private var hasPromptedForLearningNotifications = false
    @State private var status: ReminderStatus = .checking
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        Section {
            if let message {
                Text(message)
                    .foregroundStyle(status == .unavailable ? .red : .secondary)
            }

            Button {
                Task { await enableReminders() }
            } label: {
                if isWorking {
                    ProgressView()
                } else {
                    Label(actionTitle, systemImage: actionSymbol)
                }
            }
            .disabled(isWorking || status == .authorized)
            .accessibilityIdentifier("language-manager-daily-reminders")
        } header: {
            Text("Learning reminders")
        } footer: {
            Text("Voxa sends at most one daily reminder to continue learning.")
        }
        .task { await refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshStatus() }
        }
    }

    private var actionTitle: String {
        switch status {
        case .checking:
            return "Checking reminders"
        case .authorized:
            return "Daily reminders on"
        case .notDetermined:
            return "Turn on daily reminders"
        case .denied:
            return "Open iOS Settings"
        case .unavailable:
            return "Try again"
        }
    }

    private var actionSymbol: String {
        switch status {
        case .authorized:
            return "bell.fill"
        case .denied:
            return "gear"
        default:
            return "bell"
        }
    }

    @MainActor
    private func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = ReminderStatus(settings.authorizationStatus)
        message = message(for: status)
        if status == .authorized {
            scheduleDailyLearningReminder()
        }
    }

    @MainActor
    private func enableReminders() async {
        isWorking = true
        defer { isWorking = false }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            hasPromptedForLearningNotifications = true
            scheduleDailyLearningReminder()
            status = .authorized
            message = message(for: .authorized)
        case .notDetermined:
            hasPromptedForLearningNotifications = true
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                if granted {
                    scheduleDailyLearningReminder()
                    status = .authorized
                    message = message(for: .authorized)
                } else {
                    status = .denied
                    message = message(for: .denied)
                }
            } catch {
                status = .unavailable
                message = message(for: .unavailable)
            }
        case .denied:
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                openURL(settingsURL)
            }
            status = .denied
            message = message(for: .denied)
        @unknown default:
            status = .unavailable
            message = message(for: .unavailable)
        }
    }

    private func scheduleDailyLearningReminder() {
        guard let snapshot else {
            LearningReminderScheduler.removeScheduledReminders()
            return
        }
        LearningReminderScheduler.schedule(snapshot: snapshot)
    }

    private func message(for status: ReminderStatus) -> String {
        switch status {
        case .checking:
            return "Checking notification settings..."
        case .authorized:
            return "Daily reminders are enabled."
        case .notDetermined:
            return "Turn on reminders to get a daily nudge to keep your progress moving."
        case .denied:
            return "Notifications are off for Voxa. Open iOS Settings to allow reminders."
        case .unavailable:
            return "Voxa could not check notification settings. Please try again."
        }
    }

}

private enum ReminderStatus {
    case checking
    case authorized
    case notDetermined
    case denied
    case unavailable

    init(_ authorizationStatus: UNAuthorizationStatus) {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            self = .authorized
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        @unknown default:
            self = .unavailable
        }
    }
}
#endif

/// A single language row: name, a short summary, and an active marker.
private struct LanguageRow: View {
    let profile: LanguageProfile
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName.asLanguageDisplayName)
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Active language")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var summary: String {
        var parts: [String] = ["\(profile.profile.minutesPerDay) min/day"]
        parts.append(profile.profile.placementLevel.displayName)
        if !profile.isComplete {
            parts.append("Setup incomplete")
        }
        return parts.joined(separator: " • ")
    }
}

/// Detail screen for one language: switch to it (when not active) and edit its
/// settings. Reuses `LanguageSettingsView` for the editable form and refreshes
/// the caller's list once a save succeeds.
private struct LanguageDetailView: View {
    let isActive: Bool
    let onSwitch: () -> Void
    let onSaved: () async -> Void
    @State private var settingsModel: LanguageSettingsViewModel

    init(
        profile: LanguageProfile,
        isActive: Bool,
        makeSettingsModel: @MainActor (LanguageProfile) -> LanguageSettingsViewModel,
        onSwitch: @escaping () -> Void,
        onSaved: @escaping () async -> Void
    ) {
        self.isActive = isActive
        self.onSwitch = onSwitch
        self.onSaved = onSaved
        _settingsModel = State(initialValue: makeSettingsModel(profile))
    }

    var body: some View {
        LanguageSettingsView(model: settingsModel)
            .toolbar {
                if !isActive {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Make active", action: onSwitch)
                            .accessibilityIdentifier("language-manager-make-active")
                    }
                }
            }
            .onChange(of: settingsModel.state) { _, newState in
                if newState == .saved {
                    Task { await onSaved() }
                }
            }
    }
}
#endif
