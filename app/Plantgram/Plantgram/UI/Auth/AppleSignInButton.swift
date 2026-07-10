import AuthenticationServices
import SwiftUI

struct AppleSignInButton: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var currentNonce: String?

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = Nonce.random()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = nonce.sha256Hex()
        } onCompletion: { result in
            Task {
                await sessionStore.signInWithApple(result, rawNonce: currentNonce)
            }
        }
        .signInWithAppleButtonStyle(.whiteOutline)
        .disabled(sessionStore.isAuthenticating)
    }
}
