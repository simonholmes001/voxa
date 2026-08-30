import Foundation
import VoxaAuth

/// Wire DTOs for the backend app-session endpoints (`docs/api-contracts.md`,
/// PR #58). These are intentionally internal so the rest of the app depends on
/// `VoxaAuth` domain types; if the backend contract changes, only this file and
/// the mapping in `VoxaBackendAuthenticationService` change.

struct SignInWithAppleRequestDTO: Encodable {
    let identityToken: String
    let authorizationCode: String
    let nonce: String
}

struct RefreshRequestDTO: Encodable {
    let refreshToken: String
}

struct LogoutRequestDTO: Encodable {
    let refreshToken: String
}

struct AppSessionResponseDTO: Decodable {
    let correlationId: String
    let tenantId: String
    let userId: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let refreshTokenExpiresAt: Date

    func toAuthSession() -> AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            refreshTokenExpiresAt: refreshTokenExpiresAt,
            userId: userId,
            tenantId: tenantId
        )
    }
}

struct LogoutResponseDTO: Decodable {
    let correlationId: String
    let revoked: Bool
}

struct ApiErrorDTO: Decodable {
    let code: String
    let message: String
    let correlationId: String
    let retryable: Bool
}
