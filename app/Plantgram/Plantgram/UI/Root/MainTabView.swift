import SwiftUI

struct MainTabView: View {
    @State private var selectedPostType: PostType?
    @State private var feedRefreshID = 0

    var body: some View {
        TabView {
            NavigationStack {
                FeedView(refreshID: feedRefreshID)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                postTypeMenu
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Choose post type")
                        }
                    }
            }
            .tabItem {
                Label("Feed", systemImage: "leaf")
            }

            NavigationStack {
                GardenView()
            }
            .tabItem {
                Label("Garden", systemImage: "camera.macro")
            }

            NavigationStack {
                ProfileView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                postTypeMenu
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Choose post type")
                        }
                    }
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
        }
        .sheet(item: $selectedPostType, onDismiss: {
            feedRefreshID += 1
        }) { postType in
            CreatePostView(postType: postType)
        }
    }

    @ViewBuilder
    private var postTypeMenu: some View {
        ForEach(PostType.allCases) { type in
            Button {
                selectedPostType = type
            } label: {
                Label(type.title, systemImage: type.systemImage)
            }
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(SessionStore.previewSignedIn)
    }
}
