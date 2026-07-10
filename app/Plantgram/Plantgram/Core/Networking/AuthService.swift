import Foundation

struct AuthService: Sendable {
    var signInWithAppleHandler: @Sendable (_ identityToken: String, _ authorizationCode: String, _ rawNonce: String, _ userIdentifier: String, _ email: String?, _ fullName: String?) async throws -> AuthTokenResponse
    var refreshTokenHandler: @Sendable (_ refreshToken: String, _ householdId: String?) async throws -> RefreshTokenResponse

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

    func refreshToken(refreshToken: String, householdId: String?) async throws -> RefreshTokenResponse {
        try await refreshTokenHandler(refreshToken, householdId)
    }

    static let live = AuthService(
        signInWithAppleHandler: { identityToken, authorizationCode, rawNonce, userIdentifier, email, fullName in
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
        },
        refreshTokenHandler: { refreshToken, householdId in
            try await APIClient.live.post(
                "/auth/refresh",
                body: RefreshTokenRequest(refreshToken: refreshToken, householdId: householdId)
            )
        }
    )

    static let preview = AuthService(
        signInWithAppleHandler: { _, _, _, _, _, _ in
            AuthTokenResponse(accessToken: "preview-access", refreshToken: "preview-refresh", tokenType: "Bearer")
        },
        refreshTokenHandler: { _, _ in
            RefreshTokenResponse(accessToken: "new-access", refreshToken: "new-refresh", tokenType: "Bearer")
        }
    )
}
