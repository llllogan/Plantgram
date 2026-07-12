import PhotosUI
import SwiftUI

struct CreatePlantView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject var viewModel: GardenViewModel

    @State private var name = ""
    @State private var species = ""
    @State private var notes = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var previewImage: Image?
    @State private var isShowingLibrary = false
    @State private var isShowingCamera = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Photo") {
                    HStack {
                        Spacer()
                        profilePhotoButton
                        Spacer()
                    }
                }

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
                                imageData: imageData,
                                accessToken: sessionStore.accessToken
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isCreating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .photosPicker(
                isPresented: $isShowingLibrary,
                selection: $selectedPhoto,
                matching: .images
            )
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    await loadImage(from: newValue)
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CreatePlantCameraPicker { data in
                    isShowingCamera = false
                    if let data {
                        setImage(data)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var profilePhotoButton: some View {
        ZStack(alignment: .bottomTrailing) {
            Menu {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }

                Button {
                    isShowingLibrary = true
                } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                }
            } label: {
                profilePhotoTile
            }

            if previewImage != nil {
                Button {
                    selectedPhoto = nil
                    imageData = nil
                    previewImage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 24, height: 24)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Remove profile photo")
            }
        }
        .accessibilityLabel(previewImage == nil ? "Add profile photo" : "Change profile photo")
    }

    @ViewBuilder
    private var profilePhotoTile: some View {
        if let previewImage {
            previewImage
                .resizable()
                .scaledToFill()
                .frame(width: 104, height: 104)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(.green.opacity(0.14))
                .frame(width: 104, height: 104)
                .overlay {
                    Image(systemName: "camera")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            setImage(data)
        } catch {
            viewModel.message = error.localizedDescription
        }
    }

    private func setImage(_ data: Data) {
        imageData = data
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            previewImage = Image(uiImage: uiImage)
        }
        #endif
    }
}

#if canImport(UIKit)
private struct CreatePlantCameraPicker: UIViewControllerRepresentable {
    let onImagePicked: (Data?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (Data?) -> Void

        init(onImagePicked: @escaping (Data?) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImagePicked(nil)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let imageData = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9)
            onImagePicked(imageData)
        }
    }
}
#endif

struct CreatePlantView_Previews: PreviewProvider {
    static var previews: some View {
        CreatePlantView(viewModel: GardenViewModel(plantService: .preview))
            .environmentObject(SessionStore.previewSignedIn)
    }
}
