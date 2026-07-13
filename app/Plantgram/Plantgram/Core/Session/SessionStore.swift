import AuthenticationServices
import Combine
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    enum AuthState: Equatable {
        case checking
        case signedOut
        case signedIn
    }

    enum HouseholdState: Equatable {
        case unknown
        case checking
        case needsHousehold
        case active(Household)
    }

    @Published private(set) var authState: AuthState = .checking
    @Published private(set) var householdState: HouseholdState = .unknown
    @Published private(set) var currentUser: CurrentUser?
    @Published private(set) var accessToken: String?
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isCreatingHousehold = false
    @Published var authError: String?
    @Published var householdError: String?
    @Published private(set) var usernameError: String?
    @Published private(set) var isSavingUsername = false
    @Published private(set) var accountError: String?
    @Published private(set) var isDeletingAccount = false

    private let authService: AuthService
    private let accountService: AccountService
    private let userDefaults: UserDefaults
    private var pendingProfilePhotoData: Data?

    init(authService: AuthService = .live, accountService: AccountService = .live, userDefaults: UserDefaults = .standard) {
        self.authService = authService
        self.accountService = accountService
        self.userDefaults = userDefaults
        setupTokenRefresh()
    }

    private func setupTokenRefresh() {
        APIClient.live.onUnauthorized = { [weak self] in
            do {
                return try await self?.refreshAccessToken()
            } catch {
                await MainActor.run { self?.signOut() }
                return nil
            }
        }
    }

    var shouldShowHouseholdOnboarding: Bool {
        householdState == .needsHousehold && !shouldShowUsernameOnboarding
    }

    var shouldShowUsernameOnboarding: Bool {
        authState == .signedIn && currentUser?.displayName == "Plantgram User"
    }

    var shouldShowProfilePhotoOnboarding: Bool {
        guard authState == .signedIn,
              currentUser?.profileMediaId == nil,
              let userKey = onboardingUserKey else {
            return false
        }
        return !userDefaults.bool(forKey: profilePhotoOnboardingKey(for: userKey))
    }

    var shouldShowOnboarding: Bool {
        shouldShowUsernameOnboarding || shouldShowProfilePhotoOnboarding || shouldShowHouseholdOnboarding
    }

    var hasActiveHousehold: Bool {
        if case .active = householdState {
            return true
        }
        return false
    }

    var activeHousehold: Household? {
        if case .active(let household) = householdState {
            return household
        }
        return nil
    }

    func restore() async {
        guard authState == .checking else { return }
        accessToken = KeychainStore.string(for: .accessToken)
        if accessToken != nil {
            currentUser = loadStoredUser()
            authState = .signedIn
            await refreshAccountState()
        } else {
            authState = .signedOut
        }
    }

    func signInWithApple(_ result: Result<ASAuthorization, Error>, rawNonce: String?) async {
        authError = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw APIError.invalidResponse
            }
            guard let rawNonce else {
                throw APIError.message("Missing Apple sign-in nonce.")
            }
            guard let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8),
                  let authorizationCodeData = credential.authorizationCode,
                  let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
                throw APIError.message("Apple did not return the required credentials.")
            }

            let fullName: String? = {
                guard let components = credential.fullName,
                      let givenName = components.givenName?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !givenName.isEmpty else {
                    return nil
                }
                return PersonNameComponentsFormatter().string(from: components)
            }()
            let response = try await authService.signInWithApple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                rawNonce: rawNonce,
                userIdentifier: credential.user,
                email: credential.email,
                fullName: fullName
            )

            KeychainStore.save(response.accessToken, for: .accessToken)
            KeychainStore.save(response.refreshToken, for: .refreshToken)
            accessToken = response.accessToken
            currentUser = CurrentUser(id: nil, email: credential.email, displayName: fullName?.isEmpty == false ? fullName! : "Plantgram User")
            storeCurrentUser()
            authState = .signedIn
            await refreshAccountState()
        } catch {
            authError = error.localizedDescription
            authState = .signedOut
            householdState = .unknown
        }
    }

    func createHousehold(named name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            householdError = "Household name is required."
            return
        }
        guard let accessToken else {
            householdError = "Log in again before creating a household."
            return
        }

        householdError = nil
        usernameError = nil
        isCreatingHousehold = true
        defer { isCreatingHousehold = false }

        do {
            let response = try await accountService.createHousehold(name: trimmedName, accessToken: accessToken)
            KeychainStore.save(response.accessToken, for: .accessToken)
            self.accessToken = response.accessToken
            householdState = .active(response.household)
            await uploadPendingProfilePhoto()
            await refreshAccountState()
        } catch {
            householdError = error.localizedDescription
        }
    }

    func savePlantgramUsername(_ name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            usernameError = "A Plantgram username is required."
            return
        }
        guard let accessToken else {
            usernameError = "Log in again before choosing your username."
            return
        }

        usernameError = nil
        isSavingUsername = true
        defer { isSavingUsername = false }

        do {
            let response = try await accountService.updateProfile(displayName: trimmedName, accessToken: accessToken)
            currentUser = response.human
            storeCurrentUser()
        } catch {
            usernameError = error.localizedDescription
        }
    }

    func saveProfilePhoto(_ imageData: Data) async {
        guard let accessToken, let currentUser else {
            usernameError = "Log in again before adding a profile photo."
            return
        }

        usernameError = nil

        if !hasActiveHousehold {
            pendingProfilePhotoData = imageData
            completeProfilePhotoOnboarding()
            return
        }

        await uploadProfilePhoto(imageData, accessToken: accessToken, displayName: currentUser.displayName)
    }

    private func uploadProfilePhoto(_ imageData: Data, accessToken: String, displayName: String) async {
        isSavingUsername = true
        defer { isSavingUsername = false }

        do {
            let upload = try await APIClient.live.uploadImage(
                imageData,
                fileName: "profile.jpg",
                mimeType: "image/jpeg",
                accessToken: accessToken
            )
            let response = try await accountService.updateProfile(
                displayName: displayName,
                profileMediaID: upload.media.id,
                accessToken: accessToken
            )
            self.currentUser = response.human
            storeCurrentUser()
            completeProfilePhotoOnboarding()
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            usernameError = error.localizedDescription
        }
    }

    func skipProfilePhotoOnboarding() {
        pendingProfilePhotoData = nil
        guard let userKey = onboardingUserKey else { return }
        userDefaults.set(true, forKey: profilePhotoOnboardingKey(for: userKey))
    }

    private func uploadPendingProfilePhoto() async {
        guard let pendingProfilePhotoData,
              let accessToken,
              let displayName = currentUser?.displayName else {
            return
        }
        self.pendingProfilePhotoData = nil
        await uploadProfilePhoto(pendingProfilePhotoData, accessToken: accessToken, displayName: displayName)
    }

    func joinHousehold(inviteToken: String) async -> Bool {
        guard let accessToken else {
            householdError = "Log in again before joining a household."
            return false
        }
        householdError = nil
        do {
            let response = try await accountService.acceptHouseholdInvite(token: inviteToken, accessToken: accessToken)
            KeychainStore.save(response.accessToken, for: .accessToken)
            self.accessToken = response.accessToken
            await refreshAccountState()
            return true
        } catch {
            householdError = error.localizedDescription
            return false
        }
    }

    func createHouseholdInvite() async -> HouseholdInvite? {
        guard let accessToken, let household = activeHousehold else {
            householdError = "An active household is required to create an invite."
            return nil
        }
        do {
            return try await accountService.createHouseholdInvite(householdID: household.id, accessToken: accessToken)
        } catch {
            householdError = error.localizedDescription
            return nil
        }
    }

    func leaveHousehold() async {
        guard let accessToken else {
            householdError = "Log in again before leaving your household."
            return
        }
        do {
            let response = try await accountService.leaveHousehold(accessToken: accessToken)
            KeychainStore.save(response.accessToken, for: .accessToken)
            self.accessToken = response.accessToken
            await refreshAccountState()
        } catch {
            householdError = error.localizedDescription
        }
    }

    func signOut() {
        KeychainStore.delete(.accessToken)
        KeychainStore.delete(.refreshToken)
        userDefaults.removeObject(forKey: Self.userDefaultsKey)
        accessToken = nil
        currentUser = nil
        authError = nil
        householdError = nil
        usernameError = nil
        accountError = nil
        householdState = .unknown
        authState = .signedOut
    }

    func deleteAccount() async {
        guard let accessToken else {
            accountError = "Log in again before deleting your account."
            return
        }

        accountError = nil
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await accountService.deleteAccount(accessToken: accessToken)
            signOut()
        } catch {
            accountError = error.localizedDescription
        }
    }

    func refreshAccessToken() async throws -> String? {
        guard let refreshToken = KeychainStore.string(for: .refreshToken) else {
            return nil
        }
        let householdID = activeHousehold?.id
        let response = try await authService.refreshToken(refreshToken: refreshToken, householdId: householdID)
        KeychainStore.save(response.accessToken, for: .accessToken)
        KeychainStore.save(response.refreshToken, for: .refreshToken)
        self.accessToken = response.accessToken
        return response.accessToken
    }

    private func refreshAccountState() async {
        guard let accessToken else {
            householdState = .unknown
            return
        }

        let previousHouseholdState = householdState
        householdError = nil
        householdState = .checking

        do {
            let me = try await accountService.fetchMe(accessToken: accessToken)
            currentUser = me.human
            storeCurrentUser()

            let households = try await accountService.listHouseholds(accessToken: accessToken)
            if let activeHouseholdID = me.activeHouseholdId,
               let activeHousehold = households.first(where: { $0.id == activeHouseholdID }) {
                householdState = .active(activeHousehold)
                return
            }

            guard let firstHousehold = households.first else {
                householdState = .needsHousehold
                return
            }

            let response = try await accountService.setActiveHousehold(firstHousehold.id, accessToken: accessToken)
            KeychainStore.save(response.accessToken, for: .accessToken)
            self.accessToken = response.accessToken
            householdState = .active(firstHousehold)
        } catch {
            householdError = error.localizedDescription
            householdState = previousHouseholdState == .checking ? .unknown : previousHouseholdState
        }
    }

    private func loadStoredUser() -> CurrentUser? {
        guard let data = userDefaults.data(forKey: Self.userDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(CurrentUser.self, from: data)
    }

    private func storeCurrentUser() {
        guard let currentUser, let data = try? JSONEncoder().encode(currentUser) else {
            return
        }
        userDefaults.set(data, forKey: Self.userDefaultsKey)
    }

    private var onboardingUserKey: String? {
        currentUser?.id ?? currentUser?.email
    }

    private func completeProfilePhotoOnboarding() {
        guard let userKey = onboardingUserKey else { return }
        userDefaults.set(true, forKey: profilePhotoOnboardingKey(for: userKey))
    }

    private func profilePhotoOnboardingKey(for userKey: String) -> String {
        "PlantgramProfilePhotoOnboardingCompleted-\(userKey)"
    }

    private static let userDefaultsKey = "PlantgramCurrentUser"
}

extension SessionStore {
    static var previewSignedOut: SessionStore {
        let store = SessionStore(authService: .preview, accountService: .preview)
        store.authState = .signedOut
        return store
    }

    static var previewSignedIn: SessionStore {
        let store = SessionStore(authService: .preview, accountService: .preview)
        store.authState = .signedIn
        store.householdState = .active(Household(id: "hhd_preview", name: "Home", role: "owner", createdAt: nil))
        store.accessToken = "preview-token"
        store.currentUser = CurrentUser(id: "hum_preview", email: "logan@example.com", displayName: "Logan", profileMediaId: "preview")
        return store
    }

    static var previewNeedsHousehold: SessionStore {
        let store = SessionStore(authService: .preview, accountService: .preview)
        store.authState = .signedIn
        store.householdState = .needsHousehold
        store.accessToken = "preview-token"
        store.currentUser = CurrentUser(id: "hum_preview", email: "logan@example.com", displayName: "Logan", profileMediaId: "preview")
        return store
    }
}
