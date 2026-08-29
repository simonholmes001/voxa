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

    private let store: any OnboardingDraftStore
    private let service: any OnboardingService

    public init(
        store: any OnboardingDraftStore = UserDefaultsOnboardingDraftStore(),
        service: any OnboardingService = UnavailableOnboardingService()
    ) {
        self.store = store
        self.service = service
        self.draft = (try? store.load()) ?? OnboardingDraft()
        if self.draft.isCompleted {
            phase = .completed
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
        PlacementEstimator.estimate(from: draft.placementAnswers)
    }

    // MARK: - Answer capture

    public func setTargetLanguage(_ value: String) { mutate { $0.targetLanguage = value } }
    public func setNativeLanguage(_ value: String) { mutate { $0.nativeLanguage = value } }
    public func setGoal(_ value: LearningGoal) { mutate { $0.goal = value } }
    public func setMinutesPerDay(_ value: Int) { mutate { $0.minutesPerDay = value } }

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

    public func makeProfile() -> OnboardingProfile? {
        guard
            let targetLanguage = draft.targetLanguage, !targetLanguage.isEmpty,
            let nativeLanguage = draft.nativeLanguage, !nativeLanguage.isEmpty,
            let goal = draft.goal,
            let minutesPerDay = draft.minutesPerDay
        else {
            return nil
        }
        return OnboardingProfile(
            targetLanguage: targetLanguage,
            nativeLanguage: nativeLanguage,
            goal: goal,
            minutesPerDay: minutesPerDay,
            placementLevel: placementEstimate
        )
    }

    private func mutate(_ change: (inout OnboardingDraft) -> Void) {
        change(&draft)
        try? store.save(draft)
    }
}
