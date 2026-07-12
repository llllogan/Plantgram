import Combine
import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var posts: [FeedPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    private let postService: PostService
    private var nextCursor: String?
    private var hasLoadedAllPages = false

    init(postService: PostService = .live) {
        self.postService = postService
    }

    func load(accessToken: String?) async {
        guard let accessToken else {
            message = "Log in to see your household feed."
            return
        }

        posts = []
        nextCursor = nil
        hasLoadedAllPages = false
        await loadNextPage(accessToken: accessToken)
    }

    func loadNextPage(accessToken: String?) async {
        guard let accessToken,
              !isLoading,
              !hasLoadedAllPages else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await postService.fetchFeed(accessToken: accessToken, cursor: nextCursor)
            posts.append(contentsOf: response.posts)
            nextCursor = response.nextCursor
            hasLoadedAllPages = response.nextCursor == nil || response.posts.isEmpty
            message = nil
        } catch {
            if posts.isEmpty {
                message = error.localizedDescription
            }
        }
    }
}
