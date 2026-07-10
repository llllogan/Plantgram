import SwiftUI

struct PostCardView: View {
    let post: FeedPost

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(.green.opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: post.author.type == "plant" ? "leaf.fill" : "person.fill")
                            .foregroundStyle(.green)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author.displayName)
                        .font(.headline)
                    Text(post.postType.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.body)
            }

            if let imageUrl = post.imageUrl {
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 16) {
                Label("\(post.commentCount)", systemImage: "bubble")
                ForEach(post.reactions) { reaction in
                    Text("\(reaction.emoji) \(reaction.count)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary)
        }
    }
}

struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
        PostCardView(post: .preview)
            .padding()
    }
}
