/// The languages offered during onboarding.
///
/// Display names are exposed **alphabetically sorted**; the stored value is the
/// display name itself for now (a stable code/value split is tracked in the
/// multi-language work). Sorting only affects presentation order.
public enum OnboardingLanguages {
    /// The unsorted source set of supported display names.
    public static let all: [String] = [
        "French", "Spanish", "German", "Italian", "Japanese",
        "English", "Mandarin", "Portuguese",
    ]

    /// Display names in alphabetical order for pickers.
    public static let displayNames: [String] = all.sorted()
}
