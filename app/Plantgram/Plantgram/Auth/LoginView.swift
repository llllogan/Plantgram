import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.green)

                    VStack(spacing: 8) {
                        Text("Plantgram")
                            .font(.largeTitle.bold())
                        Text("Share updates from every plant in your household.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    AppleSignInButton()
                        .frame(height: 52)

                    if sessionStore.isAuthenticating {
                        ProgressView()
                    }

                    if let message = sessionStore.authError {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(24)
            .navigationTitle("Log In")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(SessionStore.previewSignedOut)
    }
}
