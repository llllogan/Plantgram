import PhotosUI
import SwiftUI

struct CreatePostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel: CreatePostViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingLibrary = false
    @State private var isShowingCamera = false

    init(postType: PostType = .general) {
        _viewModel = StateObject(wrappedValue: CreatePostViewModel(postType: postType))
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
                            let didCreate = await viewModel.create(accessToken: sessionStore.accessToken)
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
}

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
