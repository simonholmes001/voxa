/// A single self-assessment "can-do" statement used for placement, tagged with
/// the CEFR level it demonstrates.
public struct PlacementQuestion: Sendable, Equatable, Identifiable {
    public let level: CEFRLevel
    public let prompt: String

    public var id: String { level.rawValue }
}

/// Produces an initial CEFR estimate from a short self-assessment.
///
/// This is a deliberately simple, deterministic MVP estimate: a ladder of
/// can-do statements ordered from easiest to hardest. The estimate is the
/// highest level the learner affirms with no gap below it. A backend/agent
/// placement can refine this later behind the same seam.
public enum PlacementEstimator {
    public static let questions: [PlacementQuestion] = [
        PlacementQuestion(level: .a1, prompt: "I can introduce myself and use basic greetings."),
        PlacementQuestion(level: .a2, prompt: "I can handle simple, routine exchanges like shopping or directions."),
        PlacementQuestion(level: .b1, prompt: "I can describe experiences, plans, and opinions on familiar topics."),
        PlacementQuestion(level: .b2, prompt: "I can interact fluently and argue a point of view in detail."),
        PlacementQuestion(level: .c1, prompt: "I can use the language flexibly for complex or professional topics."),
    ]

    public static func estimate(from answers: [Bool]) -> CEFRLevel {
        var estimate = CEFRLevel.a1
        for (index, question) in questions.enumerated() {
            guard index < answers.count, answers[index] else { break }
            estimate = question.level
        }
        return estimate
    }
}
