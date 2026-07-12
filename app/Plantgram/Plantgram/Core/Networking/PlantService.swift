import Foundation

struct PlantService: Sendable {
    var fetchPlantsHandler: @Sendable (_ accessToken: String) async throws -> [PlantAccount]
    var createPlantHandler: @Sendable (_ name: String, _ species: String, _ notes: String, _ imageData: Data?, _ accessToken: String) async throws -> PlantAccount

    func fetchPlants(accessToken: String) async throws -> [PlantAccount] {
        try await fetchPlantsHandler(accessToken)
    }

    func createPlant(name: String, species: String, notes: String, imageData: Data? = nil, accessToken: String) async throws -> PlantAccount {
        try await createPlantHandler(name, species, notes, imageData, accessToken)
    }

    static let live = PlantService(
        fetchPlantsHandler: { accessToken in
            let response: PlantListResponse = try await APIClient.live.get("/plants", accessToken: accessToken)
            return response.plants
        },
        createPlantHandler: { name, species, notes, imageData, accessToken in
            var profileMediaID: String?
            if let imageData {
                let upload = try await APIClient.live.uploadImage(
                    imageData,
                    fileName: "plant.jpg",
                    mimeType: "image/jpeg",
                    accessToken: accessToken
                )
                profileMediaID = upload.media.id
            }
            let response: CreatePlantResponse = try await APIClient.live.post(
                "/plants",
                body: CreatePlantRequest(
                    name: name,
                    species: species,
                    notes: notes,
                    profileMediaId: profileMediaID
                ),
                accessToken: accessToken
            )
            return response.plant
        }
    )

    static let preview = PlantService(
        fetchPlantsHandler: { _ in
            [.preview]
        },
        createPlantHandler: { name, species, notes, _, _ in
            PlantAccount(
                id: "plt_preview_created",
                actorId: "act_preview_created",
                name: name,
                species: species,
                notes: notes,
                profileMediaId: nil,
                createdAt: nil
            )
        }
    )
}
