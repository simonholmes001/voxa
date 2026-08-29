import Foundation

/// The application session issued by the Voxa backend after a successful
/// Sign in with Apple exchange.
///
/// This is the client-side representation only. The exact token format and
/// lifetimes are owned by the backend contract (#17 backend, #14); keep this
/// type aligned with that contract when it lands.
public struct AuthSession: Sendable, Equatable, Codable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Whether the access token is expired (or within `leeway` of expiring).
    public func isExpired(asOf now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}

/// The proof of identity produced by Sign in with Apple that the app sends to
/// the backend to be validated and exchanged for an `AuthSession`.
public struct AppleIdentityProof: Sendable, Equatable {
    public var userID: String
    public var identityToken: Data
    public var authorizationCode: Data
    public var email: String?
    public var fullName: String?

    public init(
        userID: String,
        identityToken: Data,
        authorizationCode: Data,
        email: String? = nil,
        fullName: String? = nil
    ) {
        self.userID = userID
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.email = email
        self.fullName = fullName
    }
}
