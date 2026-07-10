import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel = FeedViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.posts.isEmpty {
                ProgressView()
            } else if viewModel.posts.isEmpty {
                EmptyStateView(
                    systemImage: "leaf",
                    title: "No Posts Yet",
                    message: viewModel.message ?? "Create the first update for your household plants."
                )
            } else {
                List(viewModel.posts) { post in
                    PostCardView(post: post)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.load(accessToken: sessionStore.accessToken)
                }
            }
        }
        .navigationTitle("Feed")
        .task {
            await viewModel.load(accessToken: sessionStore.accessToken)
        }
    }
}

struct FeedView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FeedView()
                .environmentObject(SessionStore.previewSignedIn)
        }
    }
}
