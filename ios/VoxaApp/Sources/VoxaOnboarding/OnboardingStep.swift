/// The ordered steps of the onboarding flow.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case targetLanguage
    case nativeLanguage
    case goal
    case time
    case placement
    case summary

    public var isLast: Bool { self == Self.allCases.last }
}
