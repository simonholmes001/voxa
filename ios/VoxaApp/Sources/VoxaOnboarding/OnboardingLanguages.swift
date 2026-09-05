/// A supported learning/native language: a stable BCP-47 key plus a display
/// name. The key is the canonical profile identifier used across the app and
/// sent to the backend (`targetLanguage` / `languageKey`).
public struct SupportedLanguage: Sendable, Equatable, Identifiable {
    public let key: String
    public let displayName: String

    public var id: String { key }

    public init(key: String, displayName: String) {
        self.key = key
        self.displayName = displayName
    }
}

/// The catalog of languages offered during onboarding.
public enum OnboardingLanguages {
    /// The supported languages (unsorted source set).
    public static let all: [SupportedLanguage] = [
        SupportedLanguage(key: "fr-FR", displayName: "French"),
        SupportedLanguage(key: "es-ES", displayName: "Spanish"),
        SupportedLanguage(key: "de-DE", displayName: "German"),
        SupportedLanguage(key: "it-IT", displayName: "Italian"),
        SupportedLanguage(key: "ja-JP", displayName: "Japanese"),
        SupportedLanguage(key: "en-US", displayName: "English"),
        SupportedLanguage(key: "zh-CN", displayName: "Mandarin"),
        SupportedLanguage(key: "pt-PT", displayName: "Portuguese"),
    ]

    /// Supported languages in alphabetical display order (for pickers).
    public static let sorted: [SupportedLanguage] = all.sorted { $0.displayName < $1.displayName }

    /// Display names in alphabetical order.
    public static let displayNames: [String] = sorted.map(\.displayName)

    /// The canonical key for a display name, if known.
    public static func key(forDisplayName name: String) -> String? {
        all.first { $0.displayName == name }?.key
    }

    /// The display name for a canonical key, falling back to the raw value when
    /// the key is unknown (e.g. legacy display-name values during migration).
    public static func displayName(forKey key: String) -> String {
        all.first { $0.key == key }?.displayName ?? key
    }
}
