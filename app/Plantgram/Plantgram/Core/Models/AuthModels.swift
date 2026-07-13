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
    let profileMediaId: String?

    init(id: String?, email: String?, displayName: String, profileMediaId: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.profileMediaId = profileMediaId
    }
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

struct HouseholdInvite: Decodable, Identifiable {
    let id: String
    let token: String
    let joinURL: String
    let householdName: String
    let expiresAt: String

    private enum CodingKeys: String, CodingKey {
        case id, token, joinURL, householdName, expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedURL = try container.decodeIfPresent(String.self, forKey: .joinURL)
        let decodedToken = try container.decodeIfPresent(String.self, forKey: .token)
        let token = decodedToken ?? Self.token(from: decodedURL)

        guard let token, !token.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .token,
                in: container,
                debugDescription: "Household invite is missing its token."
            )
        }

        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? token
        self.token = token
        self.joinURL = decodedURL ?? "plantgram://join?token=\(token)"
        self.householdName = try container.decodeIfPresent(String.self, forKey: .householdName) ?? "Household"
        self.expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt) ?? ""
    }

    init(id: String, token: String, joinURL: String, householdName: String, expiresAt: String) {
        self.id = id
        self.token = token
        self.joinURL = joinURL
        self.householdName = householdName
        self.expiresAt = expiresAt
    }

    private static func token(from joinURL: String?) -> String? {
        guard let joinURL, let url = URL(string: joinURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "token" })?.value
    }
}

struct CreateHouseholdInviteResponse: Decodable {
    let invite: HouseholdInvite

    private enum CodingKeys: String, CodingKey {
        case invite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let invite = try container.decodeIfPresent(HouseholdInvite.self, forKey: .invite) {
            self.invite = invite
        } else {
            self.invite = try HouseholdInvite(from: decoder)
        }
    }
}

struct AcceptHouseholdInviteRequest: Encodable {
    let token: String
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
