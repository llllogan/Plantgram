import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        Group {
            switch sessionStore.authState {
            case .checking:
                ProgressView()
            case .signedOut:
                LoginView()
            case .signedIn:
                MainTabView()
            }
        }
        .dismissKeyboardOnTap()
        .sheet(
            isPresented: Binding(
                get: { sessionStore.shouldShowUsernameOnboarding || sessionStore.shouldShowHouseholdOnboarding },
                set: { _ in }
            )
        ) {
            if sessionStore.shouldShowUsernameOnboarding {
                UsernameOnboardingSheet()
                    .environmentObject(sessionStore)
            } else {
                HouseholdOnboardingSheet()
                    .environmentObject(sessionStore)
            }
        }
        .task {
            await sessionStore.restore()
        }
    }
}

struct AppRootView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AppRootView()
                .environmentObject(SessionStore.previewSignedOut)

            AppRootView()
                .environmentObject(SessionStore.previewNeedsHousehold)
        }
    }
}
