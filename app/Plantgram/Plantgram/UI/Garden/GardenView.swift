import SwiftUI

struct GardenView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel = GardenViewModel()
    @State private var isPresentingCreatePlant = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.plants.isEmpty {
                ProgressView()
            } else if viewModel.plants.isEmpty {
                EmptyStateView(
                    systemImage: "leaf.circle",
                    title: "No Plants Yet",
                    message: viewModel.message ?? "Add the first plant in your household garden."
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                        spacing: 18
                    ) {
                        ForEach(viewModel.plants) { plant in
                            PlantGridItem(plant: plant, accessToken: sessionStore.accessToken)
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    if sessionStore.hasActiveHousehold {
                        await viewModel.load(accessToken: sessionStore.accessToken)
                    }
                }
            }
        }
        .navigationTitle("Garden")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingCreatePlant = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Plant")
                .disabled(!sessionStore.hasActiveHousehold)
            }
        }
        .sheet(isPresented: $isPresentingCreatePlant) {
            CreatePlantView(viewModel: viewModel)
        }
        .task(id: sessionStore.accessToken) {
            if sessionStore.hasActiveHousehold {
                await viewModel.load(accessToken: sessionStore.accessToken)
            }
        }
    }
}

private struct PlantGridItem: View {
    let plant: PlantAccount
    let accessToken: String?

    var body: some View {
        VStack(spacing: 8) {
            PlantProfileImage(
                mediaID: plant.profileMediaId,
                accessToken: accessToken,
                size: 72
            )

            Text(plant.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 118)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(plant.name)
    }
}

struct GardenView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            GardenView()
                .environmentObject(SessionStore.previewSignedIn)
        }
    }
}
