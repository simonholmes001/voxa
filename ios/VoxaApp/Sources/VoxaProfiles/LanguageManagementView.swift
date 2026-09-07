#if canImport(SwiftUI)
import SwiftUI

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
    private let onSignOut: () -> Void

    public init(
        profiles: [LanguageProfile],
        activeKey: String?,
        makeSettingsModel: @escaping @MainActor (LanguageProfile) -> LanguageSettingsViewModel,
        onSwitch: @escaping (LanguageProfile) -> Void,
        onAddLanguage: @escaping () -> Void,
        onSaved: @escaping () async -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.profiles = profiles
        self.activeKey = activeKey
        self.makeSettingsModel = makeSettingsModel
        self.onSwitch = onSwitch
        self.onAddLanguage = onAddLanguage
        self.onSaved = onSaved
        self.onSignOut = onSignOut
    }

    public var body: some View {
        List {
            Section("Your languages") {
                if profiles.isEmpty {
                    Text("You don't have any languages yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        NavigationLink {
                            LanguageDetailView(
                                profile: profile,
                                isActive: profile.languageKey == activeKey,
                                makeSettingsModel: makeSettingsModel,
                                onSwitch: { onSwitch(profile) },
                                onSaved: onSaved
                            )
                        } label: {
                            LanguageRow(profile: profile, isActive: profile.languageKey == activeKey)
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

            Section {
                Button(role: .destructive, action: onSignOut) {
                    Text("Sign out")
                }
                .accessibilityIdentifier("language-manager-sign-out")
            }
        }
        .navigationTitle("Languages")
    }
}

/// A single language row: name, a short summary, and an active marker.
private struct LanguageRow: View {
    let profile: LanguageProfile
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
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
