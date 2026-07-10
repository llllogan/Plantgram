import Foundation

struct PostService: Sendable {
    var fetchFeedHandler: @Sendable (_ accessToken: String) async throws -> [FeedPost]
    var createPostHandler: @Sendable (_ caption: String, _ postType: PostType, _ imageData: Data?, _ accessToken: String) async throws -> FeedPost
    var fetchCommentsHandler: @Sendable (_ postID: String, _ accessToken: String) async throws -> [PostComment]
    var addReactionHandler: @Sendable (_ postID: String, _ emoji: String, _ accessToken: String) async throws -> Void
    var removeReactionHandler: @Sendable (_ postID: String, _ emoji: String, _ accessToken: String) async throws -> Void
    var createCommentHandler: @Sendable (_ postID: String, _ body: String, _ accessToken: String) async throws -> PostComment

    func fetchFeed(accessToken: String) async throws -> [FeedPost] {
        try await fetchFeedHandler(accessToken)
    }

    func createPost(caption: String, postType: PostType, imageData: Data?, accessToken: String) async throws -> FeedPost {
        try await createPostHandler(caption, postType, imageData, accessToken)
    }

    func fetchComments(postID: String, accessToken: String) async throws -> [PostComment] {
        try await fetchCommentsHandler(postID, accessToken)
    }

    func addReaction(postID: String, emoji: String, accessToken: String) async throws {
        try await addReactionHandler(postID, emoji, accessToken)
    }

    func removeReaction(postID: String, emoji: String, accessToken: String) async throws {
        try await removeReactionHandler(postID, emoji, accessToken)
    }

    func createComment(postID: String, body: String, accessToken: String) async throws -> PostComment {
        try await createCommentHandler(postID, body, accessToken)
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
        },
        fetchCommentsHandler: { postID, accessToken in
            let response: PostCommentsResponse = try await APIClient.live.get(
                "/posts/\(postID)/comments",
                accessToken: accessToken
            )
            return response.comments
        },
        addReactionHandler: { postID, emoji, accessToken in
            let _: AddReactionResponse = try await APIClient.live.post(
                "/posts/\(postID)/reactions",
                body: AddReactionRequest(emoji: emoji),
                accessToken: accessToken
            )
        },
        removeReactionHandler: { postID, emoji, accessToken in
            guard let encodedEmoji = emoji.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                throw APIError.invalidURL
            }
            try await APIClient.live.delete(
                "/posts/\(postID)/reactions/\(encodedEmoji)",
                accessToken: accessToken
            )
        },
        createCommentHandler: { postID, body, accessToken in
            let response: CreateCommentResponse = try await APIClient.live.post(
                "/posts/\(postID)/comments",
                body: CreateCommentRequest(body: body),
                accessToken: accessToken
            )
            return response.comment
        }
    )
}
