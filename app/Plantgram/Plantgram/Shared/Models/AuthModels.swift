import Foundation

struct AuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
}

struct AppleAuthRequest: Encodable {
    let identityToken: String
    let authorizationCode: String
    let rawNonce: String
    let userIdentifier: String
    let email: String?
    let fullName: String?
}

struct CurrentUser: Codable, Equatable {
    let id: String?
    let email: String?
    let displayName: String
}

struct MeResponse: Decodable {
    let human: CurrentUser
    let activeHouseholdId: String?
}
