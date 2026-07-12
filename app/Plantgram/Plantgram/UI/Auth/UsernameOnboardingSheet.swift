import SwiftUI

struct UsernameOnboardingSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var username = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 58))
                        .foregroundStyle(.green)
                        .symbolRenderingMode(.hierarchical)

                    VStack(spacing: 8) {
                        Text("Choose your Plantgram username")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text("Apple did not provide your first name. Choose the name you would like people in your household to see.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Plantgram Username")
                        .font(.headline)
                    TextField("Your name", text: $username)
                        .textInputAutocapitalization(.words)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.white.opacity(0.28), lineWidth: 1)
                        }
                        .onSubmit { saveUsername() }
                }

                if let message = sessionStore.usernameError {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button { saveUsername() } label: {
                    Label(
                        sessionStore.isSavingUsername ? "Saving..." : "Continue",
                        systemImage: "arrow.right"
                    )
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.glassProminent)
                .tint(.green)
                .disabled(sessionStore.isSavingUsername)
                .padding(.bottom, 8)
            }
            .padding(24)
            .navigationTitle("Your Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }

    private func saveUsername() {
        Task {
            await sessionStore.savePlantgramUsername(username)
        }
    }
}
