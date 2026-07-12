import PhotosUI
import SwiftUI

struct CreatePostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel: CreatePostViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingLibrary = false
    @State private var isShowingCamera = false
    @State private var plants: [PlantAccount] = []
    @State private var selectedPlantIDs = Set<String>()
    @State private var plantLoadingError: String?

    private let plantService: PlantService

    init(postType: PostType = .general, plantService: PlantService = .live) {
        _viewModel = StateObject(wrappedValue: CreatePostViewModel(postType: postType))
        self.plantService = plantService
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        imagePickerButton

                        TextField("Caption", text: $viewModel.caption, axis: .vertical)
                            .lineLimit(5...10)
                            .textFieldStyle(.plain)
                            .frame(minHeight: 96, alignment: .top)
                    }
                    .padding(.vertical, 8)
                }

                Section("Tag Plants") {
                    if let plantLoadingError {
                        Text(plantLoadingError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if plants.isEmpty {
                        Text("No plants in this household yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                            spacing: 10
                        ) {
                            ForEach(plants) { plant in
                                plantTagButton(plant)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let message = viewModel.message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task {
                            let didCreate = await viewModel.create(
                                accessToken: sessionStore.accessToken,
                                plantIDs: Array(selectedPlantIDs),
                                imageMediaID: nil
                            )
                            if didCreate {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isPosting || !viewModel.canPost)
                }

            }
            .photosPicker(
                isPresented: $isShowingLibrary,
                selection: $selectedPhoto,
                matching: .images
            )
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    await viewModel.loadImage(from: newValue)
                }
            }
            .task(id: sessionStore.activeHousehold?.id ?? "none") {
                await loadPlants()
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraImagePicker { data in
                    isShowingCamera = false
                    if let data {
                        viewModel.loadImage(data: data)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var imagePickerButton: some View {
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
                photoTile
            }

            if viewModel.previewImage != nil {
                Button {
                    selectedPhoto = nil
                    viewModel.clearImage()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 24, height: 24)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(5)
                .accessibilityLabel("Remove photo")
            }
        }
        .accessibilityLabel(viewModel.previewImage == nil ? "Add photo" : "Change photo")
    }

    @ViewBuilder
    private var photoTile: some View {
        if let previewImage = viewModel.previewImage {
            previewImage
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 96, height: 96)
                .overlay {
                    Image(systemName: "camera")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func plantTagButton(_ plant: PlantAccount) -> some View {
        let isSelected = selectedPlantIDs.contains(plant.id)

        return Button {
            if isSelected {
                selectedPlantIDs.remove(plant.id)
            } else {
                selectedPlantIDs.insert(plant.id)
            }
        } label: {
            HStack(spacing: 6) {
                PlantProfileImage(
                    mediaID: plant.profileMediaId,
                    accessToken: sessionStore.accessToken
                )

                Text(plant.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tag \(plant.name)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func loadPlants() async {
        guard let accessToken = sessionStore.accessToken else { return }

        do {
            plants = try await plantService.fetchPlants(accessToken: accessToken)
            plantLoadingError = nil
        } catch {
            plants = []
            plantLoadingError = error.localizedDescription
        }
    }
}

#if canImport(UIKit)
struct PlantProfileImage: View {
    let mediaID: String?
    let accessToken: String?
    var size: CGFloat = 32

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.green)
            }
        }
        .frame(width: size, height: size)
        .background(.green.opacity(0.14))
        .clipShape(Circle())
        .task(id: "\(mediaID ?? "none")-\(accessToken ?? "")") {
            await load()
        }
    }

    private func load() async {
        guard let mediaID,
              let url = URL(string: "/media/\(mediaID)", relativeTo: APIClient.live.baseURL)?.absoluteURL else {
            return
        }

        do {
            var request = URLRequest(url: url)
            if let accessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let loadedImage = UIImage(data: data) else {
                return
            }
            image = loadedImage
        } catch {
            // Keep the leaf placeholder when a profile image cannot be loaded.
        }
    }
}
#else
struct PlantProfileImage: View {
    let mediaID: String?
    let accessToken: String?
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: "leaf.fill")
            .foregroundStyle(.green)
            .frame(width: size, height: size)
            .background(.green.opacity(0.14))
            .clipShape(Circle())
    }
}
#endif

#if canImport(UIKit)
private struct CameraImagePicker: UIViewControllerRepresentable {
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

struct CreatePostView_Previews: PreviewProvider {
    static var previews: some View {
        CreatePostView(postType: .wateringEvent)
            .environmentObject(SessionStore.previewSignedIn)
    }
}
