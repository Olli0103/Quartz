#if os(iOS)
import SwiftUI
import PhotosUI

/// Image source options for iOS: Photo Library, Files, Camera, Scan.
public enum ImageSourceOption {
    case photoLibrary
    case files
    case camera
    case scan
}

/// Sheet presented when user chooses an image source.
public struct ImageSourceSheet: View {
    @Binding var isPresented: Bool
    @Binding var selectedSource: ImageSourceOption?
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onComplete: () -> Void

    public init(isPresented: Binding<Bool>, selectedSource: Binding<ImageSourceOption?>, selectedPhotoItem: Binding<PhotosPickerItem?>, onComplete: @escaping () -> Void) {
        self._isPresented = isPresented
        self._selectedSource = selectedSource
        self._selectedPhotoItem = selectedPhotoItem
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            List {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(String(localized: "Photo Library", bundle: .module), systemImage: "photo.on.rectangle.angled")
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    guard newItem != nil else { return }
                    selectedSource = .photoLibrary
                    isPresented = false
                    onComplete()
                }

                Button {
                    selectedSource = .files
                    isPresented = false
                    onComplete()
                } label: {
                    Label(String(localized: "Files", bundle: .module), systemImage: "folder")
                }

                Button {
                    selectedSource = .camera
                    isPresented = false
                    onComplete()
                } label: {
                    Label(String(localized: "Camera", bundle: .module), systemImage: "camera")
                }

                Button {
                    selectedSource = .scan
                    isPresented = false
                    onComplete()
                } label: {
                    Label(String(localized: "Scan Document", bundle: .module), systemImage: "doc.viewfinder")
                }
            }
            .navigationTitle(String(localized: "Insert Image", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) {
                        isPresented = false
                    }
                }
            }
        }
    }
}
#endif
