import Foundation

struct PlantAccount: Codable, Identifiable, Equatable {
    let id: String
    let actorId: String?
    let name: String
    let species: String
    let notes: String
    let profileMediaId: String?
    let createdAt: String?
}

struct PlantListResponse: Decodable {
    let plants: [PlantAccount]

    private enum CodingKeys: String, CodingKey {
        case plants
    }

    init(plants: [PlantAccount]) {
        self.plants = plants
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plants = try container.decodeIfPresent([PlantAccount].self, forKey: .plants) ?? []
    }
}

struct CreatePlantRequest: Encodable {
    let name: String
    let species: String
    let notes: String
    let profileMediaId: String?
}

struct CreatePlantResponse: Decodable {
    let plant: PlantAccount
}

extension PlantAccount {
    static let preview = PlantAccount(
        id: "plt_preview",
        actorId: "act_preview",
        name: "Monstera",
        species: "Monstera deliciosa",
        notes: "Bright indirect light near the kitchen window.",
        profileMediaId: nil,
        createdAt: nil
    )
}
