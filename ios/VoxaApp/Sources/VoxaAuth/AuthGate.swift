#if canImport(SwiftUI)
import SwiftUI

/// Gates `content` behind authentication: shows the sign-in screen until the
/// app has a valid session, then renders the authenticated content.
public struct AuthGate<Content: View>: View {
    @Bindable private var model: AuthViewModel
    private let content: () -> Content

    public init(model: AuthViewModel, @ViewBuilder content: @escaping () -> Content) {
        self.model = model
        self.content = content
    }

    public var body: some View {
        Group {
            if model.state.isSignedIn {
                content()
            } else {
                #if canImport(AuthenticationServices)
                SignInView(model: model)
                #else
                Text("Sign in is unavailable on this platform.")
                #endif
            }
        }
    }
}
#endif
