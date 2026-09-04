import Foundation
import Observation

/// Drives the onboarding flow: step navigation, capturing answers, persisting a
/// resumable draft, computing the placement estimate, and submitting the
/// profile to the backend.
@MainActor
@Observable
public final class OnboardingViewModel {
    public enum Phase: Sendable, Equatable {
        case inProgress
        case submitting
        case completed
        case failed(String)
    }

    public private(set) var draft: OnboardingDraft
    public private(set) var phase: Phase = .inProgress

    /// Whether the time step is in "custom minutes" mode (vs a preset).
    public private(set) var isCustomTimeMode: Bool = false
    /// The text shown in the custom-minutes field.
    public private(set) var customTimeText: String = ""

    private var store: any OnboardingDraftStore
    private let service: any OnboardingService
    private let scopedStoreFactory: (_ tenantId: String, _ userId: String) -> any OnboardingDraftStore
    private var currentScope: String?

    public init(
        store: any OnboardingDraftStore = UserDefaultsOnboardingDraftStore(),
        service: any OnboardingService = LocalOnboardingService(),
        scopedStoreFactory: @escaping (_ tenantId: String, _ userId: String) -> any OnboardingDraftStore = {
            UserDefaultsOnboardingDraftStore.scoped(tenantId: $0, userId: $1)
        }
    ) {
        self.store = store
        self.service = service
        self.scopedStoreFactory = scopedStoreFactory
        self.draft = (try? store.load()) ?? OnboardingDraft()
        if self.draft.isCompleted {
            phase = .completed
        }
        syncCustomTimeState()
    }

    /// Reconstructs the transient custom-time UI state from the persisted draft
    /// (e.g. on launch, scope change, or resume), so a saved custom value shows
    /// in the field.
    private func syncCustomTimeState() {
        if let minutes = draft.minutesPerDay, !DailyTimeSelection.isPreset(minutes) {
            isCustomTimeMode = true
            customTimeText = String(minutes)
        } else {
            isCustomTimeMode = false
            customTimeText = ""
        }
    }

    public func scope(toTenantId tenantId: String, userId: String) {
        let nextScope = "\(tenantId)|\(userId)"
        guard nextScope != currentScope else { return }

        store = scopedStoreFactory(tenantId, userId)
        draft = (try? store.load()) ?? OnboardingDraft()
        phase = draft.isCompleted ? .completed : .inProgress
        currentScope = nextScope
        syncCustomTimeState()

        // Try to resume from backend if local draft is not completed
        if !draft.isCompleted {
            Task { await tryResumeFromBackend() }
        }
    }

    private func tryResumeFromBackend() async {
        do {
            if let profile = try await service.resume() {
                // Backend has a profile, so onboarding was completed on another device
                // Update local draft to reflect completion
                draft.targetLanguage = profile.targetLanguage
                draft.nativeLanguage = profile.nativeLanguage
                draft.goals = profile.goals
                draft.minutesPerDay = profile.minutesPerDay
                draft.placementLevel = profile.placementLevel
                draft.isCompleted = true
                try? store.save(draft)
                syncCustomTimeState()
                phase = .completed
            }
        } catch {
            // Resume failed or no profile exists - continue with local draft
        }
    }

    // MARK: - Derived state

    public var currentStep: OnboardingStep {
        OnboardingStep(rawValue: draft.stepIndex) ?? .welcome
    }

    public var isComplete: Bool {
        phase == .completed || draft.isCompleted
    }

    public var placementEstimate: CEFRLevel {
        draft.placementLevel ?? PlacementEstimator.estimate(from: draft.placementAnswers)
    }

    // MARK: - Answer capture

    public func setTargetLanguage(_ value: String) { mutate { $0.targetLanguage = value } }
    public func setNativeLanguage(_ value: String) { mutate { $0.nativeLanguage = value } }
    /// Selects a preset daily time and leaves custom mode.
    public func setMinutesPerDay(_ value: Int) {
        isCustomTimeMode = false
        customTimeText = ""
        mutate { $0.minutesPerDay = value }
    }

    /// Switches the time step to custom mode. Keeps an existing custom value, or
    /// clears the committed minutes so Continue stays disabled until a valid
    /// custom value is entered.
    public func enterCustomTimeMode() {
        isCustomTimeMode = true
        if let minutes = draft.minutesPerDay, !DailyTimeSelection.isPreset(minutes) {
            customTimeText = String(minutes)
        } else {
            customTimeText = ""
            mutate { $0.minutesPerDay = nil }
        }
    }

    /// Live-updates the custom minutes from the field. A valid value is
    /// committed to `minutesPerDay`; anything invalid clears it so Continue is
    /// disabled.
    public func updateCustomTime(_ text: String) {
        customTimeText = text
        switch DailyTimeSelection.validate(text) {
        case let .success(value):
            mutate { $0.minutesPerDay = value }
        case .failure:
            mutate { $0.minutesPerDay = nil }
        }
    }

    /// The current custom-time validation error to surface, or `nil` when the
    /// field is empty or valid.
    public var customTimeError: DailyTimeSelection.DailyTimeError? {
        let trimmed = customTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isCustomTimeMode, !trimmed.isEmpty else { return nil }
        if case let .failure(error) = DailyTimeSelection.validate(customTimeText) {
            return error
        }
        return nil
    }

    /// The learner's selected goals (predefined raw values and custom text).
    public var selectedGoals: [String] { draft.goals }

    public func isGoalSelected(_ value: String) -> Bool {
        draft.goals.contains(value)
    }

    /// Toggles a predefined goal on or off.
    public func togglePredefinedGoal(_ goal: LearningGoal) {
        mutate {
            if let index = $0.goals.firstIndex(of: goal.rawValue) {
                $0.goals.remove(at: index)
            } else {
                $0.goals.append(goal.rawValue)
            }
        }
    }

    /// Adds a validated custom goal. Returns `nil` on success, or the validation
    /// error to surface in the UI.
    @discardableResult
    public func addCustomGoal(_ text: String) -> GoalSelection.CustomGoalError? {
        switch GoalSelection.validatedCustomGoal(text, existing: draft.goals) {
        case let .success(value):
            mutate { $0.goals.append(value) }
            return nil
        case let .failure(error):
            return error
        }
    }

    public func removeGoal(_ value: String) {
        mutate { $0.goals.removeAll { $0 == value } }
    }

    public func answerPlacement(_ index: Int, _ value: Bool) {
        mutate {
            var answers = $0.placementAnswers
            let count = PlacementEstimator.questions.count
            if answers.count < count {
                answers.append(contentsOf: Array(repeating: false, count: count - answers.count))
            }
            guard index >= 0, index < answers.count else { return }
            answers[index] = value
            $0.placementAnswers = answers
            $0.placementLevel = PlacementEstimator.estimate(from: answers)
        }
    }

    // MARK: - Navigation

    public func advance() {
        guard !currentStep.isLast else { return }
        mutate { $0.stepIndex += 1 }
    }

    public func goBack() {
        guard draft.stepIndex > 0 else { return }
        mutate { $0.stepIndex -= 1 }
    }

    // MARK: - Completion

    /// Builds the profile from the answers and submits it. On success the flow
    /// is marked completed and the draft records completion for resume.
    public func finish() async {
        guard let profile = makeProfile() else {
            phase = .failed("Please complete every step before continuing.")
            return
        }
        phase = .submitting
        do {
            try await service.submit(profile)
            mutate { $0.isCompleted = true }
            phase = .completed
        } catch {
            phase = .failed("We couldn't save your profile. Please try again.")
        }
    }

    public func resetForFirstRunReview() {
        try? store.clear()
        draft = OnboardingDraft()
        phase = .inProgress
        currentScope = nil
    }

    public func makeProfile() -> OnboardingProfile? {
        guard
            let targetLanguage = draft.targetLanguage, !targetLanguage.isEmpty,
            let nativeLanguage = draft.nativeLanguage, !nativeLanguage.isEmpty,
            !draft.goals.isEmpty,
            let minutesPerDay = draft.minutesPerDay
        else {
            return nil
        }
        return OnboardingProfile(
            targetLanguage: targetLanguage,
            nativeLanguage: nativeLanguage,
            goals: draft.goals,
            minutesPerDay: minutesPerDay,
            placementLevel: placementEstimate
        )
    }

    private func mutate(_ change: (inout OnboardingDraft) -> Void) {
        change(&draft)
        try? store.save(draft)
    }
}
