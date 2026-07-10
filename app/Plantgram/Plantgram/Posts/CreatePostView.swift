import PhotosUI
import SwiftUI

struct CreatePostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel = CreatePostViewModel()
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        let photoButtonTitle = viewModel.selectedImageData == nil ? "Choose Photo" : "Change Photo"

        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Post Type", selection: $viewModel.postType) {
                        ForEach(PostType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                }

                Section("Caption") {
                    TextEditor(text: $viewModel.caption)
                        .frame(minHeight: 120)
                }

                Section("Image") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(photoButtonTitle, systemImage: "photo")
                    }

                    if let previewImage = viewModel.previewImage {
                        previewImage
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                if let message = viewModel.message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    await viewModel.loadImage(from: newValue)
                }
            }
        }
    }
}

struct CreatePostView_Previews: PreviewProvider {
    static var previews: some View {
        CreatePostView()
            .environmentObject(SessionStore.previewSignedIn)
    }
}
