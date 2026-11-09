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
            if let image = info[.originalImage] as? UIImage { parent.onPick(image.normalisedUp()) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// "Take a photo" and "Upload a photo", side by side. Hands back an upright UIImage.
struct PhotoSourceButtons: View {
    var takeTitle = "Take a photo"
    var onPick: (UIImage) -> Void
    @State private var showCamera = false
    @State private var item: PhotosPickerItem?

    var body: some View {
        HStack(spacing: Space.m) {
            if CameraPicker.isAvailable {
                Button { showCamera = true } label: {
                    choice(takeTitle, detail: "Opens your camera", symbol: "camera")
                }
                .buttonStyle(.plain)
            }
            PhotosPicker(selection: $item, matching: .images) {
                choice("Upload a photo", detail: "From your photo library", symbol: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker(onPick: onPick).ignoresSafeArea() }
        .onChange(of: item) { _, new in
            guard let new else { return }
            Task {
                if let data = try? await new.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    onPick(image.normalisedUp())
                }
                item = nil
            }
        }
    }

    private func choice(_ title: String, detail: String, symbol: String) -> some View {
        ChoiceTile(title: title, detail: detail, symbol: symbol)
    }
}
