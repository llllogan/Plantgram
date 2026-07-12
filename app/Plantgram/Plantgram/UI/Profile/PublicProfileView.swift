import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PublicProfileView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel: ProfileViewModel

    let reference: ProfileReference

    init(reference: ProfileReference, profileService: ProfileService = .live) {
        self.reference = reference
        _viewModel = StateObject(wrappedValue: ProfileViewModel(profileService: profileService))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.profile == nil {
                ProgressView()
            } else if let profile = viewModel.profile {
                profileContent(profile)
            } else {
                EmptyStateView(
                    systemImage: "person.crop.circle",
                    title: "Profile Unavailable",
                    message: viewModel.message ?? "This profile could not be loaded."
                )
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(reference)-\(sessionStore.accessToken ?? "")") {
            await viewModel.load(reference: reference, accessToken: sessionStore.accessToken)
        }
    }

    private func profileContent(_ profile: LoadedProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    PlantProfileImage(
                        mediaID: profile.profileMediaId,
                        accessToken: sessionStore.accessToken,
                        size: 96,
                        placeholderSystemImage: profile.reference.isHuman ? "person.fill" : "leaf.fill"
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text(profile.name)
                            .font(.title2.bold())

                        if let species = profile.species {
                            Text(species)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if case .plant = profile.reference {
                            HStack(alignment: .top, spacing: 24) {
                                ProfileStatus(
                                    label: "Last watered",
                                    value: lastWateredText(for: profile)
                                )
                                ProfileStatus(
                                    label: "Age",
                                    value: ageText(for: profile)
                                )
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)

                if profile.posts.isEmpty {
                    Text("No posts yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                        spacing: 2
                    ) {
                        ForEach(profile.posts) { post in
                            ProfilePostTile(post: post, accessToken: sessionStore.accessToken)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 16)
        }
    }

    private func lastWateredText(for profile: LoadedProfile) -> String {
        let wateringPosts = profile.posts.filter { $0.postType == .wateringEvent }
        guard let latest = wateringPosts.compactMap({ parseDate($0.occurredAt) }).max() else {
            return "Never"
        }
        return relativeDate(latest)
    }

    private func ageText(for profile: LoadedProfile) -> String {
        guard let createdAt = profile.createdAt,
              let date = parseDate(createdAt) else {
            return "Unknown"
        }
        return relativeDate(date)
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private extension ProfileReference {
    var isHuman: Bool {
        if case .human = self { return true }
        return false
    }
}

private struct ProfileStatus: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }
}

private struct ProfilePostTile: View {
    let post: FeedPost
    let accessToken: String?

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let imageURL = resolvedImageURL {
                Color.secondary.opacity(0.10)
                    .overlay { ProgressView() }
                    .task(id: "\(imageURL.absoluteString)-\(accessToken ?? "")") {
                        await loadImage(from: imageURL)
                    }
            } else {
                Color.secondary.opacity(0.10)
                Text(post.caption)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(8)
                    .padding(8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }

    private var resolvedImageURL: URL? {
        guard let imageURL = post.imageUrl else { return nil }
        if imageURL.scheme != nil { return imageURL }
        return URL(string: imageURL.absoluteString, relativeTo: APIClient.live.baseURL)?.absoluteURL
    }

    private func loadImage(from url: URL) async {
        do {
            var request = URLRequest(url: url)
            if let accessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let loadedImage = UIImage(data: data) else { return }
            image = loadedImage
        } catch {
            // Keep the tile placeholder if the image request is cancelled or fails.
        }
    }
}
