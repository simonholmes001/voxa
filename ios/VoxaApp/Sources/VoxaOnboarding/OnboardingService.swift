/// Client-side seam for submitting the completed profile to the backend, which
/// stores it and seeds the first learning plan (#20 backend).
///
/// The wire contract is a backend responsibility (#14), so the default
/// implementation fails until a real client is injected.
public protocol OnboardingService: Sendable {
    func submit(_ profile: OnboardingProfile) async throws
}

public enum OnboardingServiceError: Error, Equatable {
    case unavailable
}

/// Default service used until the backend client is injected.
public struct UnavailableOnboardingService: OnboardingService {
    public init() {}

    public func submit(_ profile: OnboardingProfile) async throws {
        throw OnboardingServiceError.unavailable
    }
}
