import PhotosUI
import SwiftUI
import UIKit

/// The camera, for "Take a photo". Only offered when the device has one (not in the Simulator).
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image.normalisedUp(maxSide: Size.photoUpload)) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// "Take a photo" and "Upload a photo", side by side. Hands back an upright UIImage.
struct PhotoSourceButtons: View {
    var takeTitle = "Take a photo"
    var onPick: (UIImage) -> Void
    @Environment(\.captureConsent) private var consent
    @State private var showCamera = false
    @State private var showLibrary = false

    var body: some View {
        HStack(spacing: Space.m) {
            if CameraPicker.isAvailable {
                Button { consent { showCamera = true } } label: {
                    choice(takeTitle, detail: "Opens your camera", symbol: "camera")
                }
                .buttonStyle(.plain)
            }
            // A button (not PhotosPicker) so the "Before you scan" notice can come first.
            Button { consent { showLibrary = true } } label: {
                choice("Upload a photo", detail: "From your photo library", symbol: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
        }
        .photoLibraryImport(isPresented: $showLibrary, onPick: onPick)
        .fullScreenCover(isPresented: $showCamera) { CameraPicker(onPick: onPick).ignoresSafeArea() }
    }

    private func choice(_ title: String, detail: String, symbol: String) -> some View {
        ChoiceTile(title: title, detail: detail, symbol: symbol)
    }
}
