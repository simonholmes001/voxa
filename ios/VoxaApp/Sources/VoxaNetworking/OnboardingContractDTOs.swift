import Foundation

/// Wire DTOs for the backend onboarding endpoint (`docs/api-contracts.md`,
/// PR #58). These are intentionally internal so the rest of the app depends on
/// `VoxaOnboarding` domain types; if the backend contract changes, only this
/// file and the mapping in `VoxaBackendOnboardingService` change.

struct OnboardingSubmitRequestDTO: Encodable {
    let targetLanguage: String
    let nativeLanguage: String
    let proficiencyLevel: String
    let goals: [String]
    let dailyMinutes: Int
}

struct OnboardingProfileDTO: Decodable {
    let targetLanguage: String
    let nativeLanguage: String
    let proficiencyLevel: String
    let goals: [String]
    let dailyMinutes: Int
}

struct OnboardingActivePlanDTO: Decodable {
    let planId: String
    let title: String
    let knowledgeUnitIds: [String]
}

struct OnboardingSubmitResponseDTO: Decodable {
    let profile: OnboardingProfileDTO
    let activePlan: OnboardingActivePlanDTO
    let version: Int
    let correlationId: String
}

struct ResumeCheckpointResponseDTO: Decodable {
    let correlationId: String
    let version: Int
    let profile: OnboardingProfileDTO
    let activePlan: OnboardingActivePlanDTO
}
