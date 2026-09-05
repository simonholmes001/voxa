import VoxaOnboarding
import VoxaProfiles

/// Wire DTOs for the language-profiles endpoints (docs/api-contracts.md).
/// Internal so a contract change stays contained to `VoxaNetworking`.

struct LanguageProfilesListResponseDTO: Decodable {
    let correlationId: String
    let activeLanguageKey: String?
    let profiles: [LanguageProfileEntryDTO]
}

struct LanguageProfileEntryDTO: Decodable {
    let languageKey: String
    let displayName: String
    let isComplete: Bool
    let profile: OnboardingProfileDTO
    let version: Int

    func toLanguageProfile() throws -> LanguageProfile {
        guard let level = CEFRLevel(rawValue: profile.proficiencyLevel.lowercased()) else {
            throw LanguageProfilesError.server(code: 200, message: "Unrecognized proficiency level.")
        }
        return LanguageProfile(
            languageKey: languageKey,
            displayName: displayName,
            isComplete: isComplete,
            profile: OnboardingProfile(
                targetLanguage: profile.targetLanguage,
                nativeLanguage: profile.nativeLanguage,
                goals: profile.goals,
                minutesPerDay: profile.dailyMinutes,
                placementLevel: level
            ),
            version: version
        )
    }
}

struct SelectLanguageResponseDTO: Decodable {
    let correlationId: String
    let activeLanguageKey: String
}
