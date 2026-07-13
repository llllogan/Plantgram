import SwiftUI
import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#endif

struct ProfileView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeleteErrorPresented = false
    @State private var isLeaveConfirmationPresented = false
    @State private var isInviteSheetPresented = false
    @State private var invite: HouseholdInvite?
    @State private var isCreatingInvite = false
    @State private var inviteError: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    PlantProfileImage(
                        mediaID: sessionStore.currentUser?.profileMediaId,
                        accessToken: sessionStore.accessToken,
                        size: 64,
                        placeholderSystemImage: "person.fill"
                    )

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

                        Spacer()

                        if household.role == "owner" {
                            Button {
                                invite = nil
                                inviteError = nil
                                isInviteSheetPresented = true
                                Task {
                                    isCreatingInvite = true
                                    invite = await sessionStore.createHouseholdInvite()
                                    isCreatingInvite = false
                                    if invite == nil {
                                        inviteError = sessionStore.householdError ?? "Unable to create a household invite."
                                    }
                                }
                            } label: {
                                if isCreatingInvite {
                                    ProgressView()
                                } else {
                                    Text("Invite")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isCreatingInvite)
                        } else {
                            Button("Leave", role: .destructive) {
                                isLeaveConfirmationPresented = true
                            }
                            .buttonStyle(.bordered)
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
                    Text("Sign Out")
                }

                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    if sessionStore.isDeletingAccount {
                        ProgressView()
                    } else {
                        Text("Delete Account")
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
        .fullScreenCover(isPresented: $isInviteSheetPresented) {
            if let invite {
                HouseholdInviteSheet(invite: invite)
            } else if let inviteError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(inviteError)
                        .multilineTextAlignment(.center)
                    Button("Done") {
                        isInviteSheetPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Creating invite…")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog(
            "Leave this household?",
            isPresented: $isLeaveConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Leave Household", role: .destructive) {
                Task { await sessionStore.leaveHousehold() }
            }
        } message: {
            Text("You will no longer see this household's plants and posts. Your account will not be deleted.")
        }
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

private struct HouseholdInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let invite: HouseholdInvite

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Invite someone to \(invite.householdName)")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                if let image = qrImage {
                    image
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 280)
                        .padding(24)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    Text("Unable to generate the invite QR code.")
                        .foregroundStyle(.secondary)
                }

                Text("Ask the other person to scan this code from the Join Household option during onboarding.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Household Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var qrImage: Image? {
        guard let data = invite.joinURL.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        #if canImport(UIKit)
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return Image(uiImage: UIImage(cgImage: cgImage))
        #else
        return nil
        #endif
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
