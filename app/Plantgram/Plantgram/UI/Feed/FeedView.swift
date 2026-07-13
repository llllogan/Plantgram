import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel = FeedViewModel()
    @StateObject private var gardenViewModel = GardenViewModel()
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
                    PostCardView(post: post, plants: gardenViewModel.plants)
//                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .onAppear {
                            guard post.id == viewModel.posts.last?.id else { return }
                            Task {
                                await viewModel.loadNextPage(accessToken: sessionStore.accessToken)
                            }
                        }
                }
                .listStyle(.plain)
                .overlay(alignment: .bottom) {
                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
                .refreshable {
                    if sessionStore.hasActiveHousehold {
                        await viewModel.load(
                            accessToken: sessionStore.accessToken,
                            householdID: sessionStore.activeHousehold?.id,
                            refreshID: refreshID,
                            force: true
                        )
                        await gardenViewModel.load(accessToken: sessionStore.accessToken)
                    }
                }
            }
        }
        .navigationTitle(sessionStore.activeHousehold?.name ?? "Feed")
        .toolbarTitleDisplayMode(.inlineLarge)
        .task(id: "\(sessionStore.accessToken ?? "")-\(sessionStore.activeHousehold?.id ?? "none")-\(refreshID)") {
            if sessionStore.hasActiveHousehold {
                await viewModel.load(
                    accessToken: sessionStore.accessToken,
                    householdID: sessionStore.activeHousehold?.id,
                    refreshID: refreshID
                )
            }
        }
        .task(id: "plants-\(sessionStore.accessToken ?? "")-\(sessionStore.activeHousehold?.id ?? "none")") {
            if sessionStore.hasActiveHousehold {
                await gardenViewModel.load(accessToken: sessionStore.accessToken)
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
