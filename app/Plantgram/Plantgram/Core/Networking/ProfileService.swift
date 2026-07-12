import Foundation

struct LoadedProfile: Sendable {
    let reference: ProfileReference
    let name: String
    let species: String?
    let profileMediaId: String?
    let createdAt: String?
    let posts: [FeedPost]
}

struct ProfileService: Sendable {
    var fetchHandler: @Sendable (_ reference: ProfileReference, _ accessToken: String) async throws -> LoadedProfile

    func fetch(reference: ProfileReference, accessToken: String) async throws -> LoadedProfile {
        try await fetchHandler(reference, accessToken)
    }

    static let live = ProfileService { reference, accessToken in
        switch reference {
        case .plant(let plantID):
            async let plantResponse: PlantProfileResponse = APIClient.live.get(
                "/plants/\(plantID)",
                accessToken: accessToken
            )
            async let postsResponse: FeedResponse = APIClient.live.get(
                "/plants/\(plantID)/timeline?limit=100",
                accessToken: accessToken
            )
            let plantResponseValue = try await plantResponse
            let plant = plantResponseValue.plant
            let postsResponseValue = try await postsResponse
            let posts = postsResponseValue.posts
            return LoadedProfile(
                reference: reference,
                name: plant.name,
                species: plant.species.isEmpty ? nil : plant.species,
                profileMediaId: plant.profileMediaId,
                createdAt: plant.createdAt,
                posts: posts
            )

        case .human(let humanID):
            async let humanResponse: HumanProfileResponse = APIClient.live.get(
                "/humans/\(humanID)",
                accessToken: accessToken
            )
            async let postsResponse: FeedResponse = APIClient.live.get(
                "/humans/\(humanID)/posts?limit=100",
                accessToken: accessToken
            )
            let humanResponseValue = try await humanResponse
            let human = humanResponseValue.human
            let postsResponseValue = try await postsResponse
            let posts = postsResponseValue.posts
            return LoadedProfile(
                reference: reference,
                name: human.displayName,
                species: nil,
                profileMediaId: human.profileMediaId,
                createdAt: human.createdAt,
                posts: posts
            )
        }
    }
}
