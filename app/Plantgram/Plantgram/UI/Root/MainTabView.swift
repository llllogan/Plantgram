import SwiftUI

struct MainTabView: View {
    @State private var isPresentingComposer = false
    @State private var feedRefreshID = 0

    var body: some View {
        TabView {
            NavigationStack {
                FeedView(refreshID: feedRefreshID)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isPresentingComposer = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("New Post")
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
                            Button {
                                isPresentingComposer = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("New Post")
                        }
                    }
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
        }
        .sheet(isPresented: $isPresentingComposer, onDismiss: {
            feedRefreshID += 1
        }) {
            CreatePostView()
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(SessionStore.previewSignedIn)
    }
}
