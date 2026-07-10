import Foundation

struct PostService {
    var fetchFeedHandler: (_ accessToken: String) async throws -> [FeedPost]
    var createPostHandler: (_ caption: String, _ postType: PostType, _ imageData: Data?, _ accessToken: String) async throws -> FeedPost

    func fetchFeed(accessToken: String) async throws -> [FeedPost] {
        try await fetchFeedHandler(accessToken)
    }

    func createPost(caption: String, postType: PostType, imageData: Data?, accessToken: String) async throws -> FeedPost {
        try await createPostHandler(caption, postType, imageData, accessToken)
    }

    static let live = PostService(
        fetchFeedHandler: { accessToken in
            let response: FeedResponse = try await APIClient.live.get("/feed", accessToken: accessToken)
            return response.posts
        },
        createPostHandler: { caption, postType, imageData, accessToken in
            var imageMediaID: String?
            if let imageData {
                let upload = try await APIClient.live.uploadImage(
                    imageData,
                    fileName: "post.jpg",
                    mimeType: "image/jpeg",
                    accessToken: accessToken
                )
                imageMediaID = upload.media.id
            }

            let response: CreatePostResponse = try await APIClient.live.post(
                "/posts",
                body: CreatePostRequest(
                    postType: postType,
                    caption: caption,
                    imageMediaId: imageMediaID,
                    plantIds: [],
                    planterIds: []
                ),
                accessToken: accessToken
            )
            return response.post
        }
    )
}
