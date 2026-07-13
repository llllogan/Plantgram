import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PostCardView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    let post: FeedPost
    let plants: [PlantAccount]
    var previewImage: Image?

    private let postService: PostService

    @State private var displayedReactions: [PostReaction]
    @State private var comments: [PostComment] = []
    @State private var isLoadingComments = false
    @State private var isCommentComposerVisible = false
    @State private var isSubmittingComment = false
    @State private var isUpdatingReaction = false
    @State private var commentText = ""
    @State private var isEmojiPickerPresented = false
    @State private var isTaggedPlantsSheetPresented = false
    
    @State private var selectedProfileReference: ProfileReference?
    @State private var interactionError: String?
    @FocusState private var isCommentFieldFocused: Bool
    @FocusState private var isReactionFieldFocused: Bool

    init(post: FeedPost, plants: [PlantAccount] = [], previewImage: Image? = nil, postService: PostService = .live) {
        self.post = post
        self.plants = plants
        self.previewImage = previewImage
        self.postService = postService
        _displayedReactions = State(initialValue: post.reactions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let authorProfileReference {
                    Button {
                        selectedProfileReference = authorProfileReference
                    } label: {
                        authorHeader
                    }
                    .buttonStyle(.plain)
                } else {
                    authorHeader
                }

                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: post.postType.systemImage)
                        .font(.caption.weight(.semibold))
                    Text(post.postType.title)
                        .font(.subheadline.weight(.semibold))
                }
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
                AuthenticatedRemoteImage(url: imageUrl, accessToken: sessionStore.accessToken)
                    .frame(maxWidth: .infinity)
            }

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.body)
                    .padding(.horizontal, 16)
            }

            reactionRow

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
        .onChange(of: isCommentFieldFocused) { _, isFocused in
            if !isFocused && commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isCommentComposerVisible = false
            }
        }
        .navigationDestination(item: $selectedProfileReference) { reference in
            PublicProfileView(reference: reference)
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

    private var authorHeader: some View {
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
        }
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

    private var reactionRow: some View {
        HStack(spacing: 14) {
            Button {
                Task { _ = await setReaction(heartEmoji) }
            } label: {
                if myHeartReaction != nil {
                    Text(heartEmoji)
                        .font(.title3)
                } else {
                    Image(systemName: "heart")
                        .font(.title3)
                }
            }
            .buttonStyle(.plain)
            .disabled(isUpdatingReaction)
            .accessibilityLabel(myHeartReaction == nil ? "Add heart reaction" : "Remove heart reaction")

            Button {
                isEmojiPickerPresented = true
            } label: {
                if let myEmojiReaction {
                    Text(myEmojiReaction.emoji)
                        .font(.title3)
                } else {
                    Image(systemName: "face.smiling")
                        .font(.title3)
                }
            }
            .buttonStyle(.plain)
            .disabled(isUpdatingReaction)
            .accessibilityLabel(myEmojiReaction == nil ? "Choose an emoji reaction" : "Change emoji reaction")

            Divider()
                .frame(height: 22)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(otherReactions) { reaction in
                        Text("\(reaction.emoji) \(reaction.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(reaction.count) \(reaction.emoji) reactions")
                    }
                }
            }

            Button {
                isTaggedPlantsSheetPresented = true
            } label: {
                Image(systemName: isTaggedPlantsSheetPresented ? "tag.fill" : "tag")
                    .font(.title3)
                    .foregroundStyle(isTaggedPlantsSheetPresented ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(taggedPlants.isEmpty)
            .accessibilityLabel(taggedPlants.isEmpty ? "No plants tagged" : "Show tagged plants")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 32)
        .sheet(isPresented: $isEmojiPickerPresented) {
            EmojiPickerSheet { emoji in
                isEmojiPickerPresented = false
                Task { _ = await setReaction(emoji) }
            }
        }
        .sheet(isPresented: $isTaggedPlantsSheetPresented) {
            TaggedPlantsSheet(
                plants: taggedPlants,
                accessToken: sessionStore.accessToken
            ) { plant in
                Task { @MainActor in
                    isTaggedPlantsSheetPresented = false
                    await Task.yield()
                    selectedProfileReference = .plant(plant.id)
                }
            }
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
            if isCancellation(error) {
                return
            }
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

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func setReaction(_ emoji: String) async -> Bool {
        guard !isUpdatingReaction else { return false }
        guard let accessToken = sessionStore.accessToken else {
            interactionError = "Log in again to react."
            return false
        }

        let previousReactions = displayedReactions
        let previousMine = displayedReactions.filter(\.mine)
        let isRemoving = emoji == heartEmoji
            ? myHeartReaction != nil
            : previousMine.contains { $0.emoji == emoji }

        for reaction in previousMine {
            removeReactionLocally(reaction)
        }

        if !isRemoving {
            if let index = displayedReactions.firstIndex(where: { $0.emoji == emoji }) {
                let reaction = displayedReactions[index]
                displayedReactions[index] = PostReaction(emoji: emoji, count: reaction.count + 1, mine: true)
            } else {
                displayedReactions.append(PostReaction(emoji: emoji, count: 1, mine: true))
            }
        }

        isUpdatingReaction = true
        interactionError = nil
        defer { isUpdatingReaction = false }

        do {
            for reaction in previousMine {
                try await postService.removeReaction(postID: post.id, emoji: reaction.emoji, accessToken: accessToken)
            }
            if !isRemoving {
                try await postService.addReaction(postID: post.id, emoji: emoji, accessToken: accessToken)
            }
            return true
        } catch {
            displayedReactions = previousReactions
            interactionError = error.localizedDescription
            return false
        }
    }

    private func removeReactionLocally(_ reaction: PostReaction) {
        guard let index = displayedReactions.firstIndex(where: { $0.emoji == reaction.emoji }) else {
            return
        }
        if reaction.count <= 1 {
            displayedReactions.remove(at: index)
        } else {
            displayedReactions[index] = PostReaction(
                emoji: reaction.emoji,
                count: reaction.count - 1,
                mine: false
            )
        }
    }

    private var myHeartReaction: PostReaction? {
        displayedReactions.first { $0.mine && heartEmojis.contains($0.emoji) }
    }

    private var myEmojiReaction: PostReaction? {
        displayedReactions.first { $0.mine && !heartEmojis.contains($0.emoji) }
    }

    private var otherReactions: [PostReaction] {
        displayedReactions.filter { !$0.mine }
    }

    private var taggedPlants: [PlantAccount] {
        plants.filter { post.plantIds.contains($0.id) }
    }

    private var authorProfileReference: ProfileReference? {
        if post.author.type == "plant", let plantID = post.plantIds.first {
            return .plant(plantID)
        }
        if let humanID = post.createdByHumanId {
            return .human(humanID)
        }
        return nil
    }

    private let heartEmoji = "❤️"
    private let heartEmojis = ["❤️", "❤", "♥️", "♥"]

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

private struct TaggedPlantsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let plants: [PlantAccount]
    let accessToken: String?
    let onSelectPlant: (PlantAccount) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 10
                ) {
                    ForEach(plants) { plant in
                        Button {
                            onSelectPlant(plant)
                        } label: {
                            HStack(spacing: 6) {
                                PlantProfileImage(
                                    mediaID: plant.profileMediaId,
                                    accessToken: accessToken
                                )

                                Text(plant.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .background(
                                Color.secondary.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Tagged Plants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
