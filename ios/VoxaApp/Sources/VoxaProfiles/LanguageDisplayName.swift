import Foundation

/// Presentation-side normalisation for a language's display name.
///
/// The onboarding flow lets learners type a custom language name as free
/// text; the raw value ("greek", "PORTUGUESE") flows to the server as-is
/// so the stable key doesn't drift. Every user-visible surface routes the
/// display name through `titleCased` to guarantee "Greek", never "greek".
///
/// Uses `localizedCapitalized` so accented and non-Latin scripts stay
/// correct (Latin/Cyrillic/Greek scripts all title-case; scripts without a
/// case distinction pass through unchanged).
public enum LanguageDisplayName {
    public static func titleCased(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }
        return trimmed.localizedCapitalized
    }
}

public extension String {
    /// Convenience so callers can write `profile.displayName.asLanguageDisplayName`.
    var asLanguageDisplayName: String {
        LanguageDisplayName.titleCased(self)
    }
}
