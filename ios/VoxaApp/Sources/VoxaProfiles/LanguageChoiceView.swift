#if canImport(SwiftUI)
import SwiftUI
import VoxaOnboarding

/// Post-sign-in chooser for a learner with more than one language profile:
/// continue an existing language or add another.
public struct LanguageChoiceView: View {
    private let profiles: [LanguageProfile]
    private let activeKey: String?
    private let onContinue: (LanguageProfile) -> Void
    private let onAddLanguage: () -> Void

    public init(
        profiles: [LanguageProfile],
        activeKey: String?,
        onContinue: @escaping (LanguageProfile) -> Void,
        onAddLanguage: @escaping () -> Void
    ) {
        self.profiles = profiles
        self.activeKey = activeKey
        self.onContinue = onContinue
        self.onAddLanguage = onAddLanguage
    }

    public var body: some View {
        List {
            Section("Continue learning") {
                ForEach(profiles) { profile in
                    Button {
                        onContinue(profile)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(.headline)
                                Text(subtitle(for: profile))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.languageKey == activeKey {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Active")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("language-choice-\(profile.languageKey)")
                }
            }

            Section {
                Button(action: onAddLanguage) {
                    Label("Add another language", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("language-add-another")
            }
        }
        .navigationTitle("Your languages")
    }

    private func subtitle(for profile: LanguageProfile) -> String {
        if profile.isComplete {
            return "Level \(profile.profile.placementLevel.displayName)"
        }
        return "Setup incomplete"
    }
}
#endif
