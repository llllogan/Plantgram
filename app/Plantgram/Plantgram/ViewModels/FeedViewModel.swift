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
    private var loadedKey: String?

    init(postService: PostService = .live) {
        self.postService = postService
    }

    func load(accessToken: String?, householdID: String? = nil, refreshID: Int = 0, force: Bool = false) async {
        guard let accessToken else {
            message = "Log in to see your household feed."
            return
        }

        let key = "\(householdID ?? "none")-\(refreshID)"
        if !force,
           loadedKey == key,
           (!posts.isEmpty || hasLoadedAllPages) {
            return
        }

        posts = []
        nextCursor = nil
        hasLoadedAllPages = false
        loadedKey = key
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
            if isCancellation(error) {
                return
            }
            if posts.isEmpty {
                message = error.localizedDescription
            }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
