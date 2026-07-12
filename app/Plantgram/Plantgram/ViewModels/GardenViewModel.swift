import Combine
import Foundation

@MainActor
final class GardenViewModel: ObservableObject {
    @Published private(set) var plants: [PlantAccount] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isCreating = false
    @Published var message: String?

    private let plantService: PlantService
    private let postService: PostService

    init(plantService: PlantService = .live, postService: PostService = .live) {
        self.plantService = plantService
        self.postService = postService
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
            if isCancellation(error) {
                return
            }
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
            let plant = try await plantService.createPlant(
                name: trimmedName,
                species: species.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                imageData: imageData,
                accessToken: accessToken
            )

            do {
                _ = try await postService.createPost(
                    caption: "Say hello to \(plant.name)",
                    postType: .plantingEvent,
                    imageData: nil,
                    plantIDs: [plant.id],
                    imageMediaID: plant.profileMediaId,
                    accessToken: accessToken
                )
            } catch {
                message = "Plant added, but the feed post could not be created."
            }

            await load(accessToken: accessToken)
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
