import Foundation

enum PostType: String, Codable, CaseIterable, Identifiable {
    case general
    case wateringEvent = "watering_event"
    case plantingEvent = "planting_event"
    case statusUpdate = "status_update"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .wateringEvent:
            "Watering"
        case .plantingEvent:
            "Planting"
        case .statusUpdate:
            "Status"
        }
    }
}

struct FeedResponse: Decodable {
    let posts: [FeedPost]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case posts
        case nextCursor
    }

    init(posts: [FeedPost], nextCursor: String?) {
        self.posts = posts
        self.nextCursor = nextCursor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        posts = try container.decodeIfPresent([FeedPost].self, forKey: .posts) ?? []
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

struct FeedPost: Decodable, Identifiable {
    let id: String
    let author: FeedActor
    let postType: PostType
    let caption: String
    let imageMediaId: String?
    let imageUrl: URL?
    let occurredAt: String
    let reactions: [PostReaction]
    let commentCount: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case author
        case postType
        case caption
        case imageMediaId
        case imageUrl
        case occurredAt
        case reactions
        case commentCount
    }

    init(
        id: String,
        author: FeedActor,
        postType: PostType,
        caption: String,
        imageMediaId: String?,
        imageUrl: URL?,
        occurredAt: String,
        reactions: [PostReaction],
        commentCount: Int
    ) {
        self.id = id
        self.author = author
        self.postType = postType
        self.caption = caption
        self.imageMediaId = imageMediaId
        self.imageUrl = imageUrl
        self.occurredAt = occurredAt
        self.reactions = reactions
        self.commentCount = commentCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        author = try container.decode(FeedActor.self, forKey: .author)
        postType = try container.decode(PostType.self, forKey: .postType)
        caption = try container.decodeIfPresent(String.self, forKey: .caption) ?? ""
        imageMediaId = try container.decodeIfPresent(String.self, forKey: .imageMediaId)
        imageUrl = try container.decodeIfPresent(URL.self, forKey: .imageUrl)
        occurredAt = try container.decodeIfPresent(String.self, forKey: .occurredAt) ?? ""
        reactions = try container.decodeIfPresent([PostReaction].self, forKey: .reactions) ?? []
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
    }
}

struct FeedActor: Decodable {
    let id: String
    let type: String
    let displayName: String
}

struct PostReaction: Decodable, Identifiable, Equatable {
    let emoji: String
    let count: Int
    let mine: Bool

    var id: String { emoji }
}

struct PostComment: Decodable, Identifiable, Equatable {
    let id: String
    let postId: String
    let humanId: String
    let body: String
    let createdAt: String
    let updatedAt: String
}

struct PostCommentsResponse: Decodable {
    let comments: [PostComment]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        comments = try container.decodeIfPresent([PostComment].self, forKey: .comments) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case comments
    }
}

struct AddReactionRequest: Encodable {
    let emoji: String
}

struct AddReactionResponse: Decodable {
    let postId: String
    let emoji: String
}

struct CreateCommentRequest: Encodable {
    let body: String
}

struct CreateCommentResponse: Decodable {
    let comment: PostComment
}

struct CreatePostRequest: Encodable {
    let postType: PostType
    let caption: String
    let imageMediaId: String?
    let plantIds: [String]
    let planterIds: [String]
}

struct CreatePostResponse: Decodable {
    let post: FeedPost
}

struct MediaUploadResponse: Decodable {
    let media: MediaAsset
}

struct MediaAsset: Decodable {
    let id: String
    let mimeType: String
    let sizeBytes: Int
    let url: String
}

extension String {
    /// A reaction is one user-perceived emoji, which may contain several Unicode scalars
    /// (for example a flag, skin tone, or family emoji joined with ZWJ characters).
    var isSingleEmojiReaction: Bool {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 1, let character = value.first else {
            return false
        }

        let scalars = Array(character.unicodeScalars)
        let hasEmojiScalar = scalars.contains { $0.properties.isEmoji }
        guard hasEmojiScalar else {
            return false
        }

        let hasEmojiPresentation = scalars.contains { $0.properties.isEmojiPresentation }
        let hasVariationSelector = scalars.contains { $0.value == 0xFE0F }
        let isTextDefaultEmojiSymbol = scalars.count == 1 && character.isSymbol

        // Some symbols, such as a heart, are valid emoji without an explicit
        // presentation selector. Digits alone are intentionally excluded.
        guard hasEmojiPresentation || hasVariationSelector || isTextDefaultEmojiSymbol else {
            return false
        }

        return scalars.allSatisfy { scalar in
            let properties = scalar.properties
            let isVariationSelector = scalar.value == 0xFE0E || scalar.value == 0xFE0F
            let isJoinControl = scalar.value == 0x200C || scalar.value == 0x200D
            let isEmojiTag = (0xE0020...0xE007F).contains(scalar.value)

            return properties.isEmoji
                || properties.isEmojiPresentation
                || properties.isEmojiModifier
                || properties.isGraphemeExtend
                || isVariationSelector
                || isJoinControl
                || isEmojiTag
        }
    }
}

extension FeedPost {
    static let preview = FeedPost(
        id: "pst_preview",
        author: FeedActor(id: "act_preview", type: "plant", displayName: "Monstera"),
        postType: .wateringEvent,
        caption: "Watered today and looking glossy.",
        imageMediaId: nil,
        imageUrl: nil,
        occurredAt: "2026-07-10T00:00:00Z",
        reactions: [PostReaction(emoji: "💚", count: 3, mine: false)],
        commentCount: 1
    )

    static let previewWithImage = FeedPost(
        id: "pst_preview_image",
        author: FeedActor(id: "act_preview", type: "human", displayName: "Logan"),
        postType: .statusUpdate,
        caption: "New growth coming through after a sunny week.",
        imageMediaId: "med_preview",
        imageUrl: URL(string: "/media/med_preview"),
        occurredAt: "2026-07-10T00:00:00Z",
        reactions: [PostReaction(emoji: "🌱", count: 2, mine: false)],
        commentCount: 0
    )
}
