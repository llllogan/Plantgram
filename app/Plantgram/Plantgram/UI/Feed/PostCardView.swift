import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PostCardView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    let post: FeedPost
    var previewImage: Image?

    private let postService: PostService
    private let reactionChoices = ["💚", "🌱", "🌿", "😍", "👏", "😂", "😮"]

    @State private var displayedReactions: [PostReaction]
    @State private var comments: [PostComment] = []
    @State private var isLoadingComments = false
    @State private var isCommentComposerVisible = false
    @State private var isSubmittingComment = false
    @State private var isUpdatingReaction = false
    @State private var commentText = ""
    @State private var interactionError: String?
    @FocusState private var isCommentFieldFocused: Bool

    init(post: FeedPost, previewImage: Image? = nil, postService: PostService = .live) {
        self.post = post
        self.previewImage = previewImage
        self.postService = postService
        _displayedReactions = State(initialValue: post.reactions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.green.opacity(0.16))
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: post.author.type == "plant" ? "leaf.fill" : "person.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }

                Text(post.author.displayName)
                    .font(.headline)

                Spacer()
                
                Text(post.postType.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            if let previewImage {
                previewImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else if let imageUrl = resolvedImageURL {
                AuthenticatedRemoteImage(url: imageUrl, accessToken: sessionStore.accessToken)
                    .frame(maxWidth: .infinity)
            }

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.body)
                    .padding(.horizontal, 16)
            }

            commentsSection

            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(displayedReactions) { reaction in
                            Button {
                                Task { await toggleReaction(reaction.emoji) }
                            } label: {
                                Text("\(reaction.emoji) \(reaction.count)")
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        reaction.mine
                                            ? Color.accentColor.opacity(0.16)
                                            : Color.secondary.opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(reaction.count) \(reaction.emoji) reactions")
                            .accessibilityHint(reaction.mine ? "Double tap to remove your reaction" : "Double tap to add your reaction")
                        }

                        Menu {
                            ForEach(reactionChoices, id: \.self) { emoji in
                                Button {
                                    Task { await toggleReaction(emoji) }
                                } label: {
                                    Text(emoji)
                                }
                            }
                        } label: {
                            Text("Add reaction")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isUpdatingReaction)
                    }
                }

                if let interactionError {
                    Text(interactionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .task(id: "\(post.id)-\(post.commentCount)") {
            await loadComments()
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoadingComments {
                ProgressView()
                    .controlSize(.small)
            }

            if comments.isEmpty && !isLoadingComments {
                Text("No comments yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !comments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(comments) { comment in
                        CommentRow(
                            comment: comment,
                            authorName: comment.humanId == sessionStore.currentUser?.id
                                ? "You"
                                : "Household member"
                        )
                    }
                }
            }

            if isCommentComposerVisible {
                commentComposer
            } else {
                Button(action: showCommentComposer) {
                    Text("Add a comment")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 16)
    }

    private var commentComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Write a comment…", text: $commentText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($isCommentFieldFocused)
                .onSubmit {
                    Task { await submitComment() }
                }

            Button {
                Task { await submitComment() }
            } label: {
                if isSubmittingComment {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSubmittingComment || commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Post comment")
        }
    }

    private func showCommentComposer() {
        isCommentComposerVisible = true
        isCommentFieldFocused = true
    }

    private func loadComments() async {
        guard !isLoadingComments else { return }
        guard let accessToken = sessionStore.accessToken else {
            interactionError = "Log in again to view comments."
            return
        }

        isLoadingComments = true
        interactionError = nil
        defer { isLoadingComments = false }

        do {
            comments = try await postService.fetchComments(postID: post.id, accessToken: accessToken)
        } catch {
            interactionError = error.localizedDescription
        }
    }

    private func submitComment() async {
        let body = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isSubmittingComment else { return }
        guard let accessToken = sessionStore.accessToken else {
            interactionError = "Log in again to comment."
            return
        }

        isSubmittingComment = true
        interactionError = nil
        defer { isSubmittingComment = false }

        do {
            let comment = try await postService.createComment(postID: post.id, body: body, accessToken: accessToken)
            comments.append(comment)
            commentText = ""
            isCommentComposerVisible = false
            isCommentFieldFocused = false
        } catch {
            interactionError = error.localizedDescription
        }
    }

    private func toggleReaction(_ emoji: String) async {
        guard !isUpdatingReaction else { return }
        guard let accessToken = sessionStore.accessToken else {
            interactionError = "Log in again to react."
            return
        }

        let previousReactions = displayedReactions
        let isRemoving: Bool

        if let index = displayedReactions.firstIndex(where: { $0.emoji == emoji }) {
            isRemoving = displayedReactions[index].mine
            let reaction = displayedReactions[index]
            if isRemoving {
                if reaction.count <= 1 {
                    displayedReactions.remove(at: index)
                } else {
                    displayedReactions[index] = PostReaction(emoji: emoji, count: reaction.count - 1, mine: false)
                }
            } else {
                displayedReactions[index] = PostReaction(emoji: emoji, count: reaction.count + 1, mine: true)
            }
        } else {
            isRemoving = false
            displayedReactions.append(PostReaction(emoji: emoji, count: 1, mine: true))
        }

        isUpdatingReaction = true
        interactionError = nil
        defer { isUpdatingReaction = false }

        do {
            if isRemoving {
                try await postService.removeReaction(postID: post.id, emoji: emoji, accessToken: accessToken)
            } else {
                try await postService.addReaction(postID: post.id, emoji: emoji, accessToken: accessToken)
            }
        } catch {
            displayedReactions = previousReactions
            interactionError = error.localizedDescription
        }
    }

    private var resolvedImageURL: URL? {
        guard let imageUrl = post.imageUrl else {
            return nil
        }
        if imageUrl.scheme != nil {
            return imageUrl
        }
        return URL(string: imageUrl.absoluteString, relativeTo: APIClient.live.baseURL)?.absoluteURL
    }
}

private struct CommentRow: View {
    let comment: PostComment
    let authorName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 4) {
                Text(authorName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                Text(comment.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#if canImport(UIKit)
private struct AuthenticatedRemoteImage: View {
    let url: URL
    let accessToken: String?

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(image.size, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            } else if didFail {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .task(id: "\(url.absoluteString)-\(accessToken ?? "")") {
            await load()
        }
    }

    private func load() async {
        image = nil
        didFail = false

        do {
            var request = URLRequest(url: url)
            if let accessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let loadedImage = UIImage(data: data) else {
                didFail = true
                return
            }
            image = loadedImage
        } catch {
            didFail = true
        }
    }
}
#endif

struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PostCardView(post: .preview)

            PostCardView(
                post: FeedPost.previewWithImage,
                previewImage: Image(systemName: "camera.macro")
            )
        }
        .padding()
        .environmentObject(SessionStore.previewSignedIn)
    }
}
