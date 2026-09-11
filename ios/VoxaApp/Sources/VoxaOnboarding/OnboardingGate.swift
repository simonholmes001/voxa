#if canImport(SwiftUI)
import SwiftUI

/// Shows onboarding until it is complete, then renders `content`.
public struct OnboardingGate<Content: View>: View {
    @Bindable private var model: OnboardingViewModel
    private let content: () -> Content

    public init(model: OnboardingViewModel, @ViewBuilder content: @escaping () -> Content) {
        self.model = model
        self.content = content
    }

    public var body: some View {
        if model.isComplete {
            content()
        } else {
            ZStack {
                OnboardingView(model: model)
                if model.phase == .submitting {
                    BuildingYourCourseOverlay()
                        .transition(.opacity)
                        .accessibilityIdentifier("onboarding-building-course-overlay")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.phase == .submitting)
        }
    }
}

/// Full-screen overlay shown during the onboarding submit while the
/// backend synchronously mints the learner's personalised course. The
/// call can take 5–15 seconds (CurriculumModel is high reasoning) —
/// this visual keeps the learner engaged so the wait feels like part
/// of the setup, not a frozen submit button.
struct BuildingYourCourseOverlay: View {
    @State private var animatedTipIndex: Int = 0

    private static let tips: [String] = [
        "Reading your goals",
        "Choosing your first lessons",
        "Sequencing the arc",
        "Naming your course",
    ]

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.4)
            Text("Building your course…")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text("Voxa is designing 20–30 lessons around your goals. This takes a few seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text(Self.tips[animatedTipIndex])
                .font(.callout)
                .foregroundStyle(.tint)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .id(animatedTipIndex)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.opacity(0.95))
        .task {
            // Cycle through the tips every 2.5s so the wait feels
            // active. The overlay dismisses when the submit resolves,
            // so this task naturally ends.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeInOut(duration: 0.3)) {
                    animatedTipIndex = (animatedTipIndex + 1) % Self.tips.count
                }
            }
        }
    }
}
#endif
