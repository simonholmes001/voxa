/// Helpers for multi-select and custom learning goals.
///
/// Goals are persisted and submitted as a `[String]` where a predefined goal is
/// stored as its `LearningGoal` raw value and a custom goal is stored as its
/// free text. `displayTitle(for:)` renders either form for the UI.
public enum GoalSelection {
    public static let maxCustomGoals = 5
    public static let maxCustomGoalLength = 40

    public enum CustomGoalError: Error, Equatable {
        case empty
        case tooLong(max: Int)
        case duplicate
        case limitReached(max: Int)
    }

    /// A display title for a stored goal value (predefined title or the custom
    /// text as entered).
    public static func displayTitle(for value: String) -> String {
        LearningGoal(rawValue: value)?.title ?? value
    }

    /// Whether a stored goal value is a custom (non-predefined) goal.
    public static func isCustom(_ value: String) -> Bool {
        LearningGoal(rawValue: value) == nil
    }

    /// Trims and validates a candidate custom goal against the existing
    /// selection, returning the normalized value or a validation error.
    public static func validatedCustomGoal(
        _ raw: String,
        existing: [String]
    ) -> Result<String, CustomGoalError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .failure(.empty)
        }
        if trimmed.count > maxCustomGoalLength {
            return .failure(.tooLong(max: maxCustomGoalLength))
        }
        if existing.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .failure(.duplicate)
        }
        let customCount = existing.filter(isCustom).count
        if customCount >= maxCustomGoals {
            return .failure(.limitReached(max: maxCustomGoals))
        }
        return .success(trimmed)
    }
}
