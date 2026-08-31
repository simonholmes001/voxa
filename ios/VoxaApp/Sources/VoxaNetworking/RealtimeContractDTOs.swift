import Foundation
import VoxaRealtime

/// Wire DTOs for `POST /api/realtime/session` (see `docs/api-contracts.md`).
/// Kept internal so a contract change stays contained to `VoxaNetworking`.

struct RealtimeSessionRequestDTO: Encodable {
    let coachingMode: String
    let proficiencyBand: String
    let targetLanguage: String
}

struct RealtimeSessionSettingsDTO: Codable {
    let coachingMode: String
    let proficiencyBand: String
    let targetLanguage: String
}

struct RealtimeSessionResponseDTO: Decodable {
    let correlationId: String
    let clientSecret: String
    let model: String
    let reasoningEffort: String
    let expiresAt: Date
    let settings: RealtimeSessionSettingsDTO

    func toCredential() -> RealtimeSessionCredential {
        RealtimeSessionCredential(
            clientSecret: clientSecret,
            model: model,
            reasoningEffort: reasoningEffort,
            expiresAt: expiresAt,
            settings: RealtimeCoachingSettings(
                coachingMode: settings.coachingMode,
                proficiencyBand: settings.proficiencyBand,
                targetLanguage: settings.targetLanguage
            )
        )
    }
}
