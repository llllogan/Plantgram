import AuthenticationServices
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    enum AuthState: Equatable {
        case checking
        case signedOut
        case signedIn
    }

    @Published private(set) var authState: AuthState = .checking
    @Published private(set) var currentUser: CurrentUser?
    @Published private(set) var accessToken: String?
    @Published private(set) var isAuthenticating = false
    @Published var authError: String?

    private let authService: AuthService
    private let userDefaults: UserDefaults

    init(authService: AuthService = .live, userDefaults: UserDefaults = .standard) {
        self.authService = authService
        self.userDefaults = userDefaults
    }

    func restore() {
        guard authState == .checking else { return }
        accessToken = KeychainStore.string(for: .accessToken)
        if accessToken != nil {
            currentUser = loadStoredUser()
            authState = .signedIn
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

            let fullName = credential.fullName.map {
                PersonNameComponentsFormatter().string(from: $0)
            }
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
        } catch {
            authError = error.localizedDescription
            authState = .signedOut
        }
    }

    func signOut() {
        KeychainStore.delete(.accessToken)
        KeychainStore.delete(.refreshToken)
        userDefaults.removeObject(forKey: Self.userDefaultsKey)
        accessToken = nil
        currentUser = nil
        authError = nil
        authState = .signedOut
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

    private static let userDefaultsKey = "PlantgramCurrentUser"
}

extension SessionStore {
    static var previewSignedOut: SessionStore {
        let store = SessionStore(authService: .preview)
        store.authState = .signedOut
        return store
    }

    static var previewSignedIn: SessionStore {
        let store = SessionStore(authService: .preview)
        store.authState = .signedIn
        store.accessToken = "preview-token"
        store.currentUser = CurrentUser(id: "hum_preview", email: "logan@example.com", displayName: "Logan")
        return store
    }
}
