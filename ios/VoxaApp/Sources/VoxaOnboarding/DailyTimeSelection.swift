/// Helpers for the daily practice-time input: presets plus a validated custom
/// value.
public enum DailyTimeSelection {
    /// Quick-pick preset minutes shown before the custom option.
    public static let presetMinutes = [5, 10, 15, 30]

    public static let minMinutes = 5
    public static let maxMinutes = 180

    public enum DailyTimeError: Error, Equatable {
        case empty
        case notANumber
        case outOfRange(min: Int, max: Int)
    }

    /// Whether a stored value is one of the presets (vs a custom entry).
    public static func isPreset(_ value: Int?) -> Bool {
        guard let value else { return false }
        return presetMinutes.contains(value)
    }

    /// Trims and validates a custom minutes entry.
    public static func validate(_ raw: String) -> Result<Int, DailyTimeError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .failure(.empty)
        }
        guard let value = Int(trimmed) else {
            return .failure(.notANumber)
        }
        guard value >= minMinutes, value <= maxMinutes else {
            return .failure(.outOfRange(min: minMinutes, max: maxMinutes))
        }
        return .success(value)
    }
}
