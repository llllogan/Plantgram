import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OnboardingSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var step: OnboardingStep = .household
    @State private var username = ""
    @State private var householdName = ""
    @State private var isCreatingHousehold = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImageData: Data?
    @State private var profilePreview: Image?
    @State private var hasAttemptedCamera = false
    @State private var isShowingLibrary = false
    @State private var isShowingCamera = false
    @State private var isShowingInviteScanner = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .username:
                    usernameStep
                case .photo:
                    photoStep
                case .household:
                    householdStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .navigationTitle("Welcome to Plantgram")
            .navigationBarTitleDisplayMode(.inline)
            .photosPicker(
                isPresented: $isShowingLibrary,
                selection: $selectedPhoto,
                matching: .images
            )
            .onChange(of: selectedPhoto) { _, newValue in
                Task { await loadProfileImage(from: newValue) }
            }
            .sheet(isPresented: $isShowingCamera) {
                OnboardingCameraPicker { data in
                    isShowingCamera = false
                    hasAttemptedCamera = true
                    if let data { setProfileImage(data) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isShowingInviteScanner) {
                HouseholdInviteScanner { scannedValue in
                    isShowingInviteScanner = false
                    guard let token = HouseholdInviteScanner.token(from: scannedValue) else {
                        sessionStore.householdError = "That QR code is not a Plantgram household invite."
                        return
                    }
                    Task {
                        _ = await sessionStore.joinHousehold(inviteToken: token)
                    }
                }
                .ignoresSafeArea()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        .task {
            if sessionStore.shouldShowUsernameOnboarding {
                step = .username
            } else if sessionStore.shouldShowProfilePhotoOnboarding {
                step = .photo
            } else {
                step = .household
            }
        }
    }

    private var usernameStep: some View {
        onboardingLayout(
            icon: "person.crop.circle.badge.checkmark",
            title: "Choose your Plantgram username",
            message: "Apple did not provide your first name. Choose the name you would like people in your household to see."
        ) {
            TextField("Your name", text: $username)
                .textInputAutocapitalization(.words)
                .textContentType(.name)
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let error = sessionStore.usernameError {
                errorText(error)
            }

            Spacer()

            Button {
                Task {
                    await sessionStore.savePlantgramUsername(username)
                    if sessionStore.usernameError == nil {
                        advanceAfterUsername()
                    }
                }
            } label: {
                Label(sessionStore.isSavingUsername ? "Saving..." : "Continue", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.glassProminent)
            .tint(.green)
            .disabled(sessionStore.isSavingUsername)
        }
    }

    private var photoStep: some View {
        onboardingLayout(
            icon: "person.crop.circle.badge.camera",
            title: "Add a profile photo",
            message: "Add a photo so your household can recognise you."
        ) {
            Menu {
                Button { isShowingCamera = true } label: {
                    Label("Take Photo", systemImage: "camera")
                }
                Button { isShowingLibrary = true } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                }
            } label: {
                ZStack {
                    if let profilePreview {
                        profilePreview
                            .resizable()
                            .scaledToFill()
                            .frame(width: 128, height: 128)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(.green.opacity(0.14))
                            .frame(width: 128, height: 128)
                            .overlay {
                                Image(systemName: "camera")
                                    .font(.largeTitle)
                                    .foregroundStyle(.green)
                            }
                    }
                }
            }
            .accessibilityLabel(profilePreview == nil ? "Add profile photo" : "Change profile photo")

            if let error = sessionStore.usernameError {
                errorText(error)
            }

            Spacer()

            Button {
                Task {
                    if let profileImageData {
                        await sessionStore.saveProfilePhoto(profileImageData)
                        if sessionStore.usernameError == nil {
                            advanceAfterPhoto()
                        }
                    } else if hasAttemptedCamera {
                        sessionStore.skipProfilePhotoOnboarding()
                        advanceAfterPhoto()
                    } else {
                        isShowingCamera = true
                    }
                }
            } label: {
                Label(
                    sessionStore.isSavingUsername ? "Saving..." : (profileImageData == nil ? "Continue" : "Save Photo"),
                    systemImage: "arrow.right"
                )
                .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.glassProminent)
            .tint(.green)
            .disabled(sessionStore.isSavingUsername)

            Button("Skip for now") {
                profileImageData = nil
                profilePreview = nil
                sessionStore.skipProfilePhotoOnboarding()
                advanceAfterPhoto()
            }
            .foregroundStyle(.secondary)
        }
    }

    private var householdStep: some View {
        onboardingLayout(
            icon: "house.and.flag.fill",
            title: "Set up your household",
            message: isCreatingHousehold ? nil : "Would you like to create or join one?"
        ) {
            if isCreatingHousehold {
                TextField("Household name", text: $householdName)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer()

                Button("Back") {
                    isCreatingHousehold = false
                }
                .buttonStyle(.glass)
                .disabled(sessionStore.isCreatingHousehold)

                Button {
                    Task { await createHousehold() }
                } label: {
                    Label(sessionStore.isCreatingHousehold ? "Creating..." : "Create Household", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.glassProminent)
                .tint(.green)
                .disabled(sessionStore.isCreatingHousehold)
            } else {
                Spacer()

                HStack(spacing: 12) {
                    Button {
                        isShowingInviteScanner = true
                    } label: {
                        Label("Join", systemImage: "person.2.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.glass)

                    Button {
                        isCreatingHousehold = true
                    } label: {
                        Label("Create", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.green)
                }
            }

            if let error = sessionStore.householdError {
                errorText(error)
            }
        }
    }

    private func onboardingLayout<Content: View>(
        icon: String,
        title: String,
        message: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if let message {
                        Text(message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.top, 24)

            content()
        }
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
    }

    private func createHousehold() async {
        await sessionStore.createHousehold(named: householdName)
    }

    private func advanceAfterUsername() {
        if sessionStore.shouldShowProfilePhotoOnboarding {
            step = .photo
        } else if sessionStore.shouldShowHouseholdOnboarding {
            step = .household
        }
    }

    private func advanceAfterPhoto() {
        if sessionStore.shouldShowHouseholdOnboarding {
            step = .household
        }
    }

    private func loadProfileImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            setProfileImage(data)
        } catch {
            if error is CancellationError { return }
            sessionStore.authError = error.localizedDescription
        }
    }

    private func setProfileImage(_ data: Data) {
        profileImageData = data
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            profilePreview = Image(uiImage: image)
        }
        #endif
    }
}

private enum OnboardingStep {
    case username
    case photo
    case household
}

#if canImport(UIKit)
private struct OnboardingCameraPicker: UIViewControllerRepresentable {
    let onImagePicked: (Data?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (Data?) -> Void

        init(onImagePicked: @escaping (Data?) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImagePicked(nil)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImagePicked((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9))
        }
    }
}
#endif
