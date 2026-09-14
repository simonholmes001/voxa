#if canImport(SwiftUI)
import SwiftUI

/// Top-level AI tutor setup surface.
///
/// Preferences are still saved per language, but this view opens directly on
/// the tutor controls so voice and style customization is easy to find.
public struct TutorSetupView: View {
    private let profiles: [LanguageProfile]
    private let activeKey: String?
    private let makeSettingsModel: @MainActor (LanguageProfile) -> LanguageSettingsViewModel
    private let onSaved: () async -> Void
    @State private var selectedLanguageKey: String?
    @State private var settingsModel: LanguageSettingsViewModel?

    public init(
        profiles: [LanguageProfile],
        activeKey: String?,
        makeSettingsModel: @escaping @MainActor (LanguageProfile) -> LanguageSettingsViewModel,
        onSaved: @escaping () async -> Void
    ) {
        self.profiles = profiles
        self.activeKey = activeKey
        self.makeSettingsModel = makeSettingsModel
        self.onSaved = onSaved

        let initialProfile = Self.initialProfile(in: profiles, activeKey: activeKey)
        _selectedLanguageKey = State(initialValue: initialProfile?.languageKey)
        _settingsModel = State(initialValue: initialProfile.map(makeSettingsModel))
    }

    public var body: some View {
        Group {
            if profiles.isEmpty {
                ContentUnavailableView(
                    "No language yet",
                    systemImage: "person.wave.2",
                    description: Text("Add a language before customizing your AI tutor.")
                )
                .navigationTitle("Tutor")
            } else {
                VStack(spacing: 0) {
                    if profiles.count > 1 {
                        languagePicker
                    }

                    if let settingsModel {
                        LanguageSettingsView(
                            model: settingsModel,
                            initialTab: .aiTutor,
                            showsTabPicker: false,
                            navigationTitle: "Tutor"
                        )
                        .onChange(of: settingsModel.state) { _, state in
                            if state == .saved {
                                Task { await onSaved() }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: selectedLanguageKey) { _, key in
            guard let profile = profile(for: key) else { return }
            settingsModel = makeSettingsModel(profile)
        }
    }

    private var languagePicker: some View {
        Picker("Language", selection: selectedLanguageBinding) {
            ForEach(profiles) { profile in
                Text(profile.displayName.asLanguageDisplayName)
                    .tag(Optional(profile.languageKey))
            }
        }
        .pickerStyle(.segmented)
        .padding([.horizontal, .top])
        .accessibilityIdentifier("tutor-setup-language-picker")
    }

    private var selectedLanguageBinding: Binding<String?> {
        Binding(
            get: { selectedLanguageKey },
            set: { selectedLanguageKey = $0 }
        )
    }

    private func profile(for key: String?) -> LanguageProfile? {
        guard let key else { return nil }
        return profiles.first { $0.languageKey == key }
    }

    private static func initialProfile(in profiles: [LanguageProfile], activeKey: String?) -> LanguageProfile? {
        if let activeKey,
           let active = profiles.first(where: { $0.languageKey == activeKey }) {
            return active
        }
        return profiles.first
    }
}
#endif
