import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PostCardView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    let post: FeedPost
    var previewImage: Image?

    private let postService: PostService

    @State private var displayedReactions: [PostReaction]
    @State private var comments: [PostComment] = []
    @State private var isLoadingComments = false
    @State private var isCommentComposerVisible = false
    @State private var isSubmittingComment = false
    @State private var isUpdatingReaction = false
    @State private var commentText = ""
    @State private var reactionText = ""
    @State private var isReactionComposerVisible = false
    @State private var interactionError: String?
    @FocusState private var isCommentFieldFocused: Bool
    @FocusState private var isReactionFieldFocused: Bool

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
                
                Label(post.postType.title, systemImage: post.postType.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .accessibilityLabel("Post type: \(post.postType.title)")
            }
            .padding(.horizontal, 16)

            if let previewImage {
                PostMediaFrame {
                    previewImage
                        .resizable()
                        .scaledToFit()
                }
            } else if let imageUrl = resolvedImageURL {
                
                VStack(alignment: .leading) {
                    AuthenticatedRemoteImage(url: imageUrl, accessToken: sessionStore.accessToken)
                        .frame(maxWidth: .infinity)
                
                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                            
                                Button(action: showReactionComposer) {
                                    Text("React")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isUpdatingReaction)
                            
                                ForEach(displayedReactions) { reaction in
                                    Button {
                                        Task { _ = await toggleReaction(reaction.emoji) }
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
                            }
                        }
                    
                        if isReactionComposerVisible {
                            reactionComposer
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            
            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.body)
                    .padding(.horizontal, 16)
            }

            if let interactionError {
                Text(interactionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            commentsSection
        }
        .padding(.vertical, 12)
        .task(id: "\(post.id)-\(post.commentCount)") {
            await loadComments()
        }
        .onChange(of: isReactionFieldFocused) { _, isFocused in
            if !isFocused {
                dismissReactionComposer()
            }
        }
        .onChange(of: isCommentFieldFocused) { _, isFocused in
            if !isFocused && commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isCommentComposerVisible = false
            }
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

    private var reactionComposer: some View {
        HStack(spacing: 8) {
            TextField("Type or paste an emoji", text: $reactionText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isReactionFieldFocused)
                .onSubmit {
                    Task { await submitReaction() }
                }

            Button {
                Task { await submitReaction() }
            } label: {
                if isUpdatingReaction {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
            .disabled(isUpdatingReaction || reactionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Add reaction")
        }
    }

    private func showCommentComposer() {
        isCommentComposerVisible = true
        isCommentFieldFocused = true
    }

    private func showReactionComposer() {
        isReactionComposerVisible = true
        isReactionFieldFocused = true
    }

    private func dismissReactionComposer() {
        guard isReactionComposerVisible else { return }
        isReactionComposerVisible = false
        reactionText = ""
    }

    private func submitReaction() async {
        let emoji = reactionText.trimmingCharacters(in: .whitespacesAndNewlines)
        interactionError = nil
        guard emoji.isSingleEmojiReaction else {
            interactionError = "Enter one emoji. Flags, skin tones, and family emojis are supported."
            return
        }

        if await toggleReaction(emoji) {
            reactionText = ""
            isReactionComposerVisible = false
            isReactionFieldFocused = false
        }
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

    private func toggleReaction(_ emoji: String) async -> Bool {
        guard !isUpdatingReaction else { return false }
        guard let accessToken = sessionStore.accessToken else {
            interactionError = "Log in again to react."
            return false
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
            return true
        } catch {
            displayedReactions = previousReactions
            interactionError = error.localizedDescription
            return false
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

private struct PostMediaFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.08)
            content
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipped()
    }
}

#if canImport(UIKit)
private struct AuthenticatedRemoteImage: View {
    private static let imageCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 100
        return cache
    }()

    let url: URL
    let accessToken: String?

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        PostMediaFrame {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else if didFail {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: image != nil)
        .task(id: "\(url.absoluteString)-\(accessToken ?? "")") {
            await load()
        }
    }

    private func load() async {
        didFail = false

        if let cachedImage = Self.imageCache.object(forKey: url as NSURL) {
            image = cachedImage
            return
        }

        image = nil

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
            Self.imageCache.setObject(loadedImage, forKey: url as NSURL)
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
