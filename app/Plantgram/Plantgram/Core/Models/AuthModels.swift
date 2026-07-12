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

struct Household: Codable, Equatable {
    let id: String
    let name: String
    let role: String?
    let createdAt: String?
}

struct HouseholdListResponse: Decodable {
    let households: [Household]

    private enum CodingKeys: String, CodingKey {
        case households
    }

    init(households: [Household]) {
        self.households = households
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        households = try container.decodeIfPresent([Household].self, forKey: .households) ?? []
    }
}

struct CreateHouseholdRequest: Encodable {
    let name: String
}

struct CreateHouseholdResponse: Decodable {
    let household: Household
    let accessToken: String
}

struct SetActiveHouseholdRequest: Encodable {
    let householdId: String
}

struct UpdateProfileRequest: Encodable {
    let displayName: String
    let profileMediaId: String?
}

struct ActiveHouseholdResponse: Decodable {
    let accessToken: String
    let tokenType: String
}

struct RefreshTokenRequest: Encodable {
    let refreshToken: String
    let householdId: String?
}

struct RefreshTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
}
