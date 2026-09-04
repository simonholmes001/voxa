import Foundation

public final class FakeProfileProvider: ProfileProvider {
    public var profile: LearnerProfile?
    public var resumeResult: LearnerProfile?

    public init(profile: LearnerProfile? = nil, resumeResult: LearnerProfile? = nil) {
        self.profile = profile
        self.resumeResult = resumeResult
    }

    public func currentProfile() async throws -> LearnerProfile? {
        return profile
    }

    public func resumeSession() async throws -> LearnerProfile? {
        // Simulate asynchronous resume latency
        try? await Task.sleep(nanoseconds: 50_000_000)
        return resumeResult
    }
}
