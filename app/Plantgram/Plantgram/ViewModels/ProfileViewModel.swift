import Combine
import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: LoadedProfile?
    @Published private(set) var isLoading = false
    @Published var message: String?

    private let profileService: ProfileService

    init(profileService: ProfileService = .live) {
        self.profileService = profileService
    }

    func load(reference: ProfileReference, accessToken: String?) async {
        guard let accessToken else {
            message = "Log in to view this profile."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            profile = try await profileService.fetch(reference: reference, accessToken: accessToken)
            message = nil
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            message = error.localizedDescription
        }
    }
}
