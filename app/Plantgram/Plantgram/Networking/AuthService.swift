import Foundation

struct AuthService: Sendable {
    var signInWithAppleHandler: @Sendable (_ identityToken: String, _ authorizationCode: String, _ rawNonce: String, _ userIdentifier: String, _ email: String?, _ fullName: String?) async throws -> AuthTokenResponse

    func signInWithApple(
        identityToken: String,
        authorizationCode: String,
        rawNonce: String,
        userIdentifier: String,
        email: String?,
        fullName: String?
    ) async throws -> AuthTokenResponse {
        try await signInWithAppleHandler(identityToken, authorizationCode, rawNonce, userIdentifier, email, fullName)
    }

    static let live = AuthService { identityToken, authorizationCode, rawNonce, userIdentifier, email, fullName in
        try await APIClient.live.post(
            "/auth/apple",
            body: AppleAuthRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                rawNonce: rawNonce,
                userIdentifier: userIdentifier,
                email: email,
                fullName: fullName
            )
        )
    }

    static let preview = AuthService { _, _, _, _, _, _ in
        AuthTokenResponse(accessToken: "preview-access", refreshToken: "preview-refresh", tokenType: "Bearer")
    }
}
