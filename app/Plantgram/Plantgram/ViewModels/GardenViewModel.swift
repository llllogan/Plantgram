import Combine
import Foundation

@MainActor
final class GardenViewModel: ObservableObject {
    @Published private(set) var plants: [PlantAccount] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isCreating = false
    @Published var message: String?

    private let plantService: PlantService

    init(plantService: PlantService = .live) {
        self.plantService = plantService
    }

    func load(accessToken: String?) async {
        guard let accessToken else {
            message = "Log in to see your garden."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            plants = try await plantService.fetchPlants(accessToken: accessToken)
            message = nil
        } catch {
            plants = []
            message = error.localizedDescription
        }
    }

    func createPlant(name: String, species: String, notes: String, imageData: Data? = nil, accessToken: String?) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            message = "Plant name is required."
            return false
        }
        guard let accessToken else {
            message = "Log in again before adding a plant."
            return false
        }

        isCreating = true
        defer { isCreating = false }

        do {
            _ = try await plantService.createPlant(
                name: trimmedName,
                species: species.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                imageData: imageData,
                accessToken: accessToken
            )
            await load(accessToken: accessToken)
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}
