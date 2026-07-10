import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel = FeedViewModel()
    let refreshID: Int

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
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
                .listStyle(.plain)
                .refreshable {
                    if sessionStore.hasActiveHousehold {
                        await viewModel.load(accessToken: sessionStore.accessToken)
                    }
                }
            }
        }
        .navigationTitle("Feed")
        .toolbarTitleDisplayMode(.inlineLarge)
        .task(id: "\(sessionStore.accessToken ?? "")-\(sessionStore.activeHousehold?.id ?? "none")-\(refreshID)") {
            if sessionStore.hasActiveHousehold {
                await viewModel.load(accessToken: sessionStore.accessToken)
            }
        }
    }
}

struct FeedView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FeedView(refreshID: 0)
                .environmentObject(SessionStore.previewSignedIn)
        }
    }
}
