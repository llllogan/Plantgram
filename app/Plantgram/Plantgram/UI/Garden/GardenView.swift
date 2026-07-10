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
                List(viewModel.plants) { plant in
                    PlantRowView(plant: plant)
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

private struct PlantRowView: View {
    let plant: PlantAccount

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.green.opacity(0.16))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "leaf.fill")
                        .foregroundStyle(.green)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(plant.name)
                    .font(.headline)

                if !plant.species.isEmpty {
                    Text(plant.species)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !plant.notes.isEmpty {
                    Text(plant.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
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
