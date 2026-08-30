import Foundation

/// The application session issued by the Voxa backend after a successful
/// Sign in with Apple exchange.
///
/// Mirrors the backend `POST /api/auth/apple` / `refresh` response contract
/// (see `docs/api-contracts.md`). The networking layer owns the wire DTOs and
/// maps them into this type, so a contract change stays contained to
/// `VoxaNetworking`.
public struct AuthSession: Sendable, Equatable, Codable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var refreshTokenExpiresAt: Date
    public var userId: String
    public var tenantId: String

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        refreshTokenExpiresAt: Date,
        userId: String,
        tenantId: String
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.userId = userId
        self.tenantId = tenantId
    }

    /// Whether the access token is expired (or within `leeway` of expiring).
    public func isExpired(asOf now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }

    /// Whether the refresh token itself has expired, meaning the session cannot
    /// be renewed and the learner must sign in again.
    public func isRefreshExpired(asOf now: Date = Date()) -> Bool {
        now >= refreshTokenExpiresAt
    }
}

/// The proof of identity produced by Sign in with Apple that the app sends to
/// the backend to be validated and exchanged for an `AuthSession`.
///
/// `nonce` is the raw nonce whose SHA-256 hash was supplied to Apple in the
/// authorization request; the backend re-hashes it to validate the identity
/// token.
public struct AppleIdentityProof: Sendable, Equatable {
    public var identityToken: Data
    public var authorizationCode: Data
    public var nonce: String
    public var userID: String
    public var email: String?
    public var fullName: String?

    public init(
        identityToken: Data,
        authorizationCode: Data,
        nonce: String,
        userID: String,
        email: String? = nil,
        fullName: String? = nil
    ) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.nonce = nonce
        self.userID = userID
        self.email = email
        self.fullName = fullName
    }
}
