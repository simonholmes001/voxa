#if canImport(SwiftUI) && canImport(AuthenticationServices)
import SwiftUI
import AuthenticationServices
import CryptoKit
import os
import Security

/// The Sign in with Apple screen shown when the app has no valid session.
public struct SignInView: View {
    private static let logger = Logger(subsystem: "com.simonholmes.voxa", category: "authentication")

    @Bindable private var model: AuthViewModel
    @State private var currentNonce = ""

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
                let nonce = Self.randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = Self.sha256(nonce)
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
        guard case let .success(authorization) = result else {
            if case let .failure(error) = result {
                Self.logger.error("Apple authorization failed domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code, privacy: .public)")
            }
            return
        }
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityToken = credential.identityToken,
            let authorizationCode = credential.authorizationCode,
            !currentNonce.isEmpty
        else {
            Self.logger.error("Apple authorization returned incomplete credentials")
            return
        }

        let formattedName = credential.fullName.map {
            PersonNameComponentsFormatter().string(from: $0)
        }
        let proof = AppleIdentityProof(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: currentNonce,
            userID: credential.user,
            email: credential.email,
            fullName: (formattedName?.isEmpty == false) ? formattedName : nil
        )
        Task { await model.signIn(with: proof) }
    }

    /// Generates a cryptographically random nonce string. The raw value is sent
    /// to the backend; its SHA-256 hash is supplied to Apple in the request.
    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var byte: UInt8 = 0
            if SecRandomCopyBytes(kSecRandomDefault, 1, &byte) != errSecSuccess {
                byte = UInt8.random(in: 0...255)
            }
            if Int(byte) < charset.count {
                result.append(charset[Int(byte)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
#endif
