import Combine
import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var posts: [FeedPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    private let postService: PostService

    init(postService: PostService = .live) {
        self.postService = postService
    }

    func load(accessToken: String?) async {
        guard let accessToken else {
            message = "Log in to see your household feed."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            posts = try await postService.fetchFeed(accessToken: accessToken)
            message = nil
        } catch {
            posts = []
            message = error.localizedDescription
        }
    }
}
