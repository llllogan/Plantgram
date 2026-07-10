import Combine
import PhotosUI
import SwiftUI

@MainActor
final class CreatePostViewModel: ObservableObject {
    @Published var postType: PostType = .general
    @Published var caption = ""
    @Published private(set) var selectedImageData: Data?
    @Published private(set) var previewImage: Image?
    @Published private(set) var isPosting = false
    @Published private(set) var message: String?

    private let postService: PostService

    var canPost: Bool {
        !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImageData != nil
    }

    init(postService: PostService = .live) {
        self.postService = postService
    }

    func loadImage(from item: PhotosPickerItem?) async {
        guard let item else {
            selectedImageData = nil
            previewImage = nil
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                message = "Could not read that photo."
                return
            }
            selectedImageData = data
            #if canImport(UIKit)
            if let uiImage = UIImage(data: data) {
                previewImage = Image(uiImage: uiImage)
            }
            #endif
        } catch {
            message = error.localizedDescription
        }
    }

    func create(accessToken: String?) async -> Bool {
        guard let accessToken else {
            message = "Log in again before posting."
            return false
        }

        isPosting = true
        defer { isPosting = false }

        do {
            _ = try await postService.createPost(
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                postType: postType,
                imageData: selectedImageData,
                accessToken: accessToken
            )
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}
