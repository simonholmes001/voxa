import Observation
import VoxaOnboarding
import VoxaRealtime

/// Edits the settings for a single language profile — native language, goals,
/// daily minutes, and placement level — and saves them to the backend using the
/// profile's version as the concurrency token. The target language is the
/// profile key and is not editable here (adding a language is a separate flow).
@MainActor
@Observable
public final class LanguageSettingsViewModel {
    public enum State: Sendable, Equatable {
        case editing
        case saving
        case saved
        case versionConflict
        case failed(String)
    }

    public let languageKey: String
    public let displayName: String

    public private(set) var state: State = .editing
    public var nativeLanguage: String
    public private(set) var goals: [String]
    public private(set) var minutesPerDay: Int?
    public var placementLevel: CEFRLevel
    public var aiTutorPreferences: AiTutorPreferences
    public private(set) var previewState: AiTutorPreviewState = .idle

    private var version: Int
    private let service: any LanguageSettingsService
    private let aiTutorPreferencesStore: (any AiTutorPreferencesStore)?
    private let previewer: (@MainActor (RealtimeCoachingSettings) async throws -> Void)?

    public init(
        profile: LanguageProfile,
        service: any LanguageSettingsService,
        aiTutorPreferencesStore: (any AiTutorPreferencesStore)? = nil,
        previewer: (@MainActor (RealtimeCoachingSettings) async throws -> Void)? = nil
    ) {
        self.languageKey = profile.languageKey
        self.displayName = profile.displayName
        self.nativeLanguage = profile.profile.nativeLanguage
        self.goals = profile.profile.goals
        self.minutesPerDay = profile.profile.minutesPerDay
        self.placementLevel = profile.profile.placementLevel
        self.aiTutorPreferences = aiTutorPreferencesStore?.preferences(for: profile.languageKey) ?? .default
        self.version = profile.version
        self.service = service
        self.aiTutorPreferencesStore = aiTutorPreferencesStore
        self.previewer = previewer
    }

    public var currentVersion: Int { version }

    // MARK: - Goal editing (mirrors onboarding rules)

    public func isGoalSelected(_ value: String) -> Bool { goals.contains(value) }

    public func togglePredefinedGoal(_ goal: LearningGoal) {
        if let index = goals.firstIndex(of: goal.rawValue) {
            goals.remove(at: index)
        } else {
            goals.append(goal.rawValue)
        }
    }

    @discardableResult
    public func addCustomGoal(_ text: String) -> GoalSelection.CustomGoalError? {
        switch GoalSelection.validatedCustomGoal(text, existing: goals) {
        case let .success(value):
            goals.append(value)
            return nil
        case let .failure(error):
            return error
        }
    }

    public func removeGoal(_ value: String) {
        goals.removeAll { $0 == value }
    }

    // MARK: - Daily time editing

    public func setMinutesPerDay(_ value: Int) { minutesPerDay = value }

    @discardableResult
    public func setCustomMinutes(_ text: String) -> DailyTimeSelection.DailyTimeError? {
        switch DailyTimeSelection.validate(text) {
        case let .success(value):
            minutesPerDay = value
            return nil
        case let .failure(error):
            return error
        }
    }

    public func setPlacementLevel(_ level: CEFRLevel) { placementLevel = level }

    public var canPreviewTutor: Bool { previewer != nil }

    public func previewTutor() async {
        guard let previewer else {
            previewState = .failed("Voice preview isn't configured for this build yet.")
            return
        }
        guard previewState != .playing else { return }
        previewState = .playing
        let settings = RealtimeCoachingSettings(
            proficiencyBand: Self.proficiencyBand(for: placementLevel),
            targetLanguage: languageKey,
            nativeLanguage: OnboardingLanguages.displayName(forKey: nativeLanguage).asLanguageDisplayName,
            aiTutorPreferences: aiTutorPreferences
        ).applying(.voicePreview)

        do {
            try await previewer(settings)
            previewState = .played
        } catch {
            previewState = .failed("We couldn't play that preview. Please try again.")
        }
    }

    // MARK: - Save

    public var canSave: Bool {
        !nativeLanguage.isEmpty && !goals.isEmpty && minutesPerDay != nil
    }

    public func save() async {
        guard let minutes = minutesPerDay, !goals.isEmpty, !nativeLanguage.isEmpty else {
            state = .failed("Please complete every field before saving.")
            return
        }
        state = .saving
        let updated = OnboardingProfile(
            targetLanguage: languageKey,
            nativeLanguage: nativeLanguage,
            goals: goals,
            minutesPerDay: minutes,
            placementLevel: placementLevel
        )
        do {
            version = try await service.update(
                languageKey: languageKey, profile: updated, expectedVersion: version
            )
            aiTutorPreferencesStore?.save(aiTutorPreferences, for: languageKey)
            state = .saved
        } catch LanguageProfilesError.versionConflict {
            state = .versionConflict
        } catch {
            state = .failed("We couldn't save your changes. Please try again.")
        }
    }

    private static func proficiencyBand(for level: CEFRLevel) -> String {
        switch level {
        case .a1, .a2: return "A1-A2"
        case .b1, .b2: return "B1-B2"
        case .c1, .c2: return "C1-C2"
        }
    }
}

public enum AiTutorPreviewState: Sendable, Equatable {
    case idle
    case playing
    case played
    case failed(String)
}
