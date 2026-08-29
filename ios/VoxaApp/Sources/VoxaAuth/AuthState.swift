/// The observable authentication state that drives the app's auth gate.
public enum AuthState: Sendable, Equatable {
    case signedOut
    case authenticating
    case signedIn(AuthSession)
    case failed(String)

    public var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }

    public var session: AuthSession? {
        if case let .signedIn(session) = self { return session }
        return nil
    }
}
