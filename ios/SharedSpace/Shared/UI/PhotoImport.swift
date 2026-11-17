import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// Choosing a photo from the library: PhotosPicker → the file's bytes (HEIC, JPEG, PNG…) → a
// downsized, upright UIImage. Decoding goes through ImageIO, which reads HEIC natively, applies the
// EXIF orientation and scales in one step without ever holding the full-size bitmap in memory.

/// What went wrong, in words for the person using the app.
enum PhotoImportError: LocalizedError {
    /// The picker handed back nothing (often an iCloud photo that couldn't be downloaded).
    case noData
    /// Bytes arrived but aren't an image ImageIO can read.
    case unreadable
    case underlying(Error)

    var errorDescription: String? { "Couldn’t add that photo" }

    var recoverySuggestion: String? {
        switch self {
        case .noData:
            "The photo couldn’t be loaded. If it’s stored in iCloud, check you’re online and try again, or choose a different photo."
        case .unreadable:
            "That file isn’t a photo Shared Space can read. Try a JPEG, HEIC or PNG photo."
        case .underlying(let error):
            "The photo couldn’t be loaded (\(error.localizedDescription)). Try again, or choose a different photo."
        }
    }
}

/// The raw bytes of whatever image type the library has, without asking Photos to convert it.
private struct PickedImageData: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { PickedImageData(data: $0) }
    }
}

enum PhotoImport {
    /// Loads a picked photo, downsized so its longest side is at most `maxSide` pixels.
    static func load(_ item: PhotosPickerItem, maxSide: CGFloat = Size.photoUpload) async throws -> UIImage {
        let picked: PickedImageData?
        do {
            picked = try await item.loadTransferable(type: PickedImageData.self)
        } catch {
            throw PhotoImportError.underlying(error)
        }
        guard let data = picked?.data, !data.isEmpty else { throw PhotoImportError.noData }
        // Decoding a 12-megapixel HEIC takes a moment; keep it off the main thread.
        return try await Task.detached(priority: .userInitiated) { try decode(data, maxSide: maxSide) }.value
    }

    /// Any ImageIO-readable image (HEIC, JPEG, PNG, …) → an upright UIImage no bigger than `maxSide`.
    static func decode(_ data: Data, maxSide: CGFloat = Size.photoUpload) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw PhotoImportError.unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // applies the EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: Int(maxSide),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoImportError.unreadable
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

/// Presents the photo library and hands back the chosen photo, ready to save. Shows a spinner while
/// it loads and an alert if it can't be read.
private struct PhotoLibraryImport: ViewModifier {
    @Binding var isPresented: Bool
    var onPick: (UIImage) -> Void
    @State private var item: PhotosPickerItem?
    @State private var loading = false
    @State private var error: PhotoImportError?

    func body(content: Content) -> some View {
        content
            // `.current` keeps the original format (usually HEIC) instead of converting it first.
            .photosPicker(isPresented: $isPresented, selection: $item, matching: .images,
                          preferredItemEncoding: .current)
            .onChange(of: item) { _, new in
                guard let new else { return }
                loading = true
                Task {
                    defer { loading = false; item = nil }
                    do {
                        onPick(try await PhotoImport.load(new))
                    } catch let failure as PhotoImportError {
                        error = failure
                    } catch {
                        self.error = .underlying(error)
                    }
                }
            }
            .overlay {
                if loading {
                    ProgressView("Adding photo…")
                        .padding(Space.l)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
            .alert(isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }), error: error) { _ in
                Button("Choose another photo") {
                    // Wait for the alert to finish closing, or the picker won't present.
                    Task { try? await Task.sleep(for: .milliseconds(450)); isPresented = true }
                }
                Button("Cancel", role: .cancel) {}
            } message: { error in
                Text(error.recoverySuggestion ?? "")
            }
    }
}

extension View {
    /// The photo library, for "Upload a photo" and "Choose from library".
    func photoLibraryImport(isPresented: Binding<Bool>, onPick: @escaping (UIImage) -> Void) -> some View {
        modifier(PhotoLibraryImport(isPresented: isPresented, onPick: onPick))
    }
}
