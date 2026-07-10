import SwiftUI

struct MainTabView: View {
    @State private var isPresentingComposer = false

    var body: some View {
        TabView {
            NavigationStack {
                FeedView()
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
        .sheet(isPresented: $isPresentingComposer) {
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
