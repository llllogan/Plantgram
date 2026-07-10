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
}

struct FeedActor: Decodable {
    let id: String
    let type: String
    let displayName: String
}

struct PostReaction: Decodable, Identifiable {
    let emoji: String
    let count: Int
    let mine: Bool

    var id: String { emoji }
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
}
