#if canImport(SwiftUI) && canImport(AuthenticationServices)
import SwiftUI
import AuthenticationServices

/// The Sign in with Apple screen shown when the app has no valid session.
public struct SignInView: View {
    @Bindable private var model: AuthViewModel

    public init(model: AuthViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Welcome to Voxa")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Your AI language tutor")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            Spacer()
            if case let .failed(message) = model.state {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("sign-in-error")
            }
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .disabled(model.state == .authenticating)
            .accessibilityIdentifier("sign-in-with-apple")
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        guard
            case let .success(authorization) = result,
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityToken = credential.identityToken,
            let authorizationCode = credential.authorizationCode
        else {
            return
        }

        let formattedName = credential.fullName.map {
            PersonNameComponentsFormatter().string(from: $0)
        }
        let proof = AppleIdentityProof(
            userID: credential.user,
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            email: credential.email,
            fullName: (formattedName?.isEmpty == false) ? formattedName : nil
        )
        Task { await model.signIn(with: proof) }
    }
}
#endif
