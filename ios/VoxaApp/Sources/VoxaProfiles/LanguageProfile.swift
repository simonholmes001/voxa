import VoxaOnboarding

/// One of a learner's language profiles, as returned by
/// `GET /api/language-profiles` (see docs/api-contracts.md).
public struct LanguageProfile: Sendable, Equatable, Identifiable {
    /// BCP-47 tag and stable profile key (e.g. "fr-FR").
    public let languageKey: String
    public let displayName: String
    public let isComplete: Bool
    public let profile: OnboardingProfile
    /// Concurrency token for subsequent updates.
    public let version: Int

    public var id: String { languageKey }

    public init(
        languageKey: String,
        displayName: String,
        isComplete: Bool,
        profile: OnboardingProfile,
        version: Int
    ) {
        self.languageKey = languageKey
        self.displayName = displayName
        self.isComplete = isComplete
        self.profile = profile
        self.version = version
    }
}

/// The learner's language-profile list plus the server-owned active key.
public struct LanguageProfileList: Sendable, Equatable {
    public let activeLanguageKey: String?
    public let profiles: [LanguageProfile]

    public init(activeLanguageKey: String?, profiles: [LanguageProfile]) {
        self.activeLanguageKey = activeLanguageKey
        self.profiles = profiles
    }
}
