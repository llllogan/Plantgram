import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Circle()
                        .fill(.green.opacity(0.16))
                        .frame(width: 64, height: 64)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(sessionStore.currentUser?.displayName ?? "Plantgram User")
                            .font(.headline)
                        if let email = sessionStore.currentUser?.email, !email.isEmpty {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                Button(role: .destructive) {
                    sessionStore.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Profile")
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ProfileView()
                .environmentObject(SessionStore.previewSignedIn)
        }
    }
}
