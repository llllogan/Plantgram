import SwiftUI

struct CreatePlantView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject var viewModel: GardenViewModel

    @State private var name = ""
    @State private var species = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Plant") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Species", text: $species)
                        .textInputAutocapitalization(.words)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let message = viewModel.message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isCreating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            if await viewModel.createPlant(
                                name: name,
                                species: species,
                                notes: notes,
                                accessToken: sessionStore.accessToken
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isCreating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct CreatePlantView_Previews: PreviewProvider {
    static var previews: some View {
        CreatePlantView(viewModel: GardenViewModel(plantService: .preview))
            .environmentObject(SessionStore.previewSignedIn)
    }
}
