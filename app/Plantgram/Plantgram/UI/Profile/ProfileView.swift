import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeleteErrorPresented = false

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

            Section("Household") {
                if let household = sessionStore.activeHousehold {
                    HStack(spacing: 12) {
                        Image(systemName: "house.fill")
                            .foregroundStyle(.green)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(household.name)
                                .font(.headline)
                            if let role = household.role, !role.isEmpty {
                                Text(role.capitalized)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else if sessionStore.householdState == .checking {
                    HStack {
                        ProgressView()
                        Text("Loading household")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("No household selected", systemImage: "house")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    sessionStore.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section {
                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    if sessionStore.isDeletingAccount {
                        ProgressView()
                    } else {
                        Label("Delete Account", systemImage: "trash")
                    }
                }
                .disabled(sessionStore.isDeletingAccount)

                Text("This permanently deletes your account, posts, and comments. Households with other members will be transferred to another member.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profile")
        .toolbarTitleDisplayMode(.inlineLarge)
        .confirmationDialog(
            "Delete your account?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task {
                    await sessionStore.deleteAccount()
                    if sessionStore.accountError != nil {
                        isDeleteErrorPresented = true
                    }
                }
            }
        } message: {
            Text("This cannot be undone. Your posts and comments will be permanently deleted. Any household you own with other members will be transferred to another member.")
        }
        .alert("Unable to delete account", isPresented: $isDeleteErrorPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(sessionStore.accountError ?? "Please try again.")
        }
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
