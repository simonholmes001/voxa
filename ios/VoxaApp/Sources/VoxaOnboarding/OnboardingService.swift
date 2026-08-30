/// Client-side seam for submitting the completed profile to the backend, which
/// stores it and seeds the first learning plan (#20 backend).
///
/// The wire contract is a backend responsibility (#14), so the default
/// implementation fails until a real client is injected.
public protocol OnboardingService: Sendable {
    func submit(_ profile: OnboardingProfile) async throws
    func resume() async throws -> OnboardingProfile?
}

public enum OnboardingServiceError: Error, Equatable {
    case unavailable
    case notFound
}

/// Default service until the backend `/api/onboarding` client is wired
/// (tracked as a follow-up issue). It completes onboarding locally without a
/// network call, so first-run onboarding is not blocked on the backend.
public struct LocalOnboardingService: OnboardingService {
    public init() {}

    public func submit(_ profile: OnboardingProfile) async throws {}
    
    public func resume() async throws -> OnboardingProfile? {
        return nil
    }
}

/// Service that always fails, useful for tests that assert failure handling.
public struct UnavailableOnboardingService: OnboardingService {
    public init() {}

    public func submit(_ profile: OnboardingProfile) async throws {
        throw OnboardingServiceError.unavailable
    }
    
    public func resume() async throws -> OnboardingProfile? {
        throw OnboardingServiceError.unavailable
    }
}
