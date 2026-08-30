import Foundation

/// Secure storage for the persisted application session.
public protocol SessionStore: Sendable {
    func load() throws -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear() throws
}

/// Non-persistent in-memory session store for previews, tests, and platforms
/// without Keychain access.
public final class EphemeralSessionStore: SessionStore, @unchecked Sendable {
    private var session: AuthSession?

    public init(session: AuthSession? = nil) {
        self.session = session
    }

    public func load() throws -> AuthSession? { session }
    public func save(_ session: AuthSession) throws { self.session = session }
    public func clear() throws { session = nil }
}
