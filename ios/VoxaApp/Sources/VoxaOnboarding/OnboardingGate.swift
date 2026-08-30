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
            OnboardingView(model: model)
        }
    }
}
#endif
