/// Why the learner wants to study the language. Kept short so first-run UX is
/// not overloaded; richer motivation is captured later by the tutor.
public enum LearningGoal: String, CaseIterable, Sendable, Codable, Identifiable {
    case travel
    case work
    case family
    case exams
    case culture
    case general

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .travel: return "Travel"
        case .work: return "Work & career"
        case .family: return "Family & friends"
        case .exams: return "Exams"
        case .culture: return "Culture & media"
        case .general: return "General fluency"
        }
    }
}

/// The learner profile produced by onboarding and submitted to the backend to
/// seed the first learning plan.
public struct OnboardingProfile: Sendable, Equatable, Codable {
    public var targetLanguage: String
    public var nativeLanguage: String
    public var goal: LearningGoal
    public var minutesPerDay: Int
    public var placementLevel: CEFRLevel

    public init(
        targetLanguage: String,
        nativeLanguage: String,
        goal: LearningGoal,
        minutesPerDay: Int,
        placementLevel: CEFRLevel
    ) {
        self.targetLanguage = targetLanguage
        self.nativeLanguage = nativeLanguage
        self.goal = goal
        self.minutesPerDay = minutesPerDay
        self.placementLevel = placementLevel
    }
}

/// The in-progress onboarding answers, persisted so an interrupted onboarding
/// can be resumed. Fields are optional until the learner supplies them.
public struct OnboardingDraft: Sendable, Equatable, Codable {
    public var targetLanguage: String?
    public var nativeLanguage: String?
    public var goal: LearningGoal?
    public var minutesPerDay: Int?
    public var placementLevel: CEFRLevel?
    public var placementAnswers: [Bool]
    public var stepIndex: Int
    public var isCompleted: Bool

    public init(
        targetLanguage: String? = nil,
        nativeLanguage: String? = nil,
        goal: LearningGoal? = nil,
        minutesPerDay: Int? = nil,
        placementLevel: CEFRLevel? = nil,
        placementAnswers: [Bool] = [],
        stepIndex: Int = 0,
        isCompleted: Bool = false
    ) {
        self.targetLanguage = targetLanguage
        self.nativeLanguage = nativeLanguage
        self.goal = goal
        self.minutesPerDay = minutesPerDay
        self.placementLevel = placementLevel
        self.placementAnswers = placementAnswers
        self.stepIndex = stepIndex
        self.isCompleted = isCompleted
    }
}
