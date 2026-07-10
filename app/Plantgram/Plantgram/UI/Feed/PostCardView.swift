import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PostCardView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    let post: FeedPost
    var previewImage: Image?

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

            HStack(spacing: 16) {
                Label("\(post.commentCount)", systemImage: "bubble")
                ForEach(post.reactions) { reaction in
                    Text("\(reaction.emoji) \(reaction.count)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
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
