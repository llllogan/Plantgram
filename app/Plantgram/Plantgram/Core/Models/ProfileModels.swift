import Foundation

enum ProfileReference: Hashable {
    case plant(String)
    case human(String)

    var id: String {
        switch self {
        case .plant(let id):
            "plant-\(id)"
        case .human(let id):
            "human-\(id)"
        }
    }
}

struct HumanProfile: Decodable {
    let id: String
    let displayName: String
    let profileMediaId: String?
    let createdAt: String?
}

struct HumanProfileResponse: Decodable {
    let human: HumanProfile
}

struct PlantProfileResponse: Decodable {
    let plant: PlantAccount
}
