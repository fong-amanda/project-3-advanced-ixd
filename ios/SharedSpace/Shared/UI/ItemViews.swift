import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Item pictures: thumbnails, crops of the room photo, and the photo cache.

/// Square thumbnail for an item: its own photo, else a crop of the room photo around its pin,
/// else its category icon.
struct ItemThumb: View {
    let item: Item
    var size: CGFloat = Size.thumbnail
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                CategoryGlyph(category: item.category, side: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        if item.photoPath != nil, let own = UIImage(contentsOfFile: FileStore.itemPhotoURL(roomId: item.roomId, itemId: item.id).path(percentEncoded: false)) {
            return own
        }
        guard let x = item.pinX, let y = item.pinY else { return nil }
        return PhotoCrops.crop(roomId: item.roomId, photo: item.pinPhoto, at: CGPoint(x: x, y: y), revision: sync.photoRevision)
    }
}

/// An item kind's icon on a quiet tile, tinted with the item's material colour.
struct CategoryGlyph: View {
    let category: ItemCategory
    var colorHex: String?
    var side: CGFloat = Size.thumbnail
    /// A fixed glyph size; otherwise it scales with `side`.
    var glyph: Font.Glyph?
    var fill: Color = .surfaceMuted

    var body: some View {
        ZStack {
            fill
            Image(systemName: category.symbol)
                .font(glyph.map { Font.glyph($0) } ?? .glyph(fitting: min(side, Size.cardImageMax / 2)))
                .foregroundStyle(Color.material(colorHex ?? category.colorHex))
        }
        .accessibilityHidden(true)
    }
}

/// Square crops of a room photo around a pin, cached.
@MainActor
enum PhotoCrops {
    private static let cache = NSCache<NSString, UIImage>()

    /// Drops cached crops (after a room is deleted).
    static func purge() { cache.removeAllObjects() }

    static func crop(roomId: UUID, photo: Int, at point: CGPoint, revision: Int, zoom: CGFloat = 0.34) -> UIImage? {
        let key = "\(roomId)-\(photo)-\(point.x)-\(point.y)-\(zoom)-\(revision)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let photo = RoomPhotos.image(roomId: roomId, index: photo, revision: revision),
              let cg = photo.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let side = min(w, h) * zoom
        let rect = CGRect(x: min(max(point.x * w - side / 2, 0), w - side),
                          y: min(max(point.y * h - side / 2, 0), h - side), width: side, height: side)
        guard let cut = cg.cropping(to: rect.integral) else { return nil }
        let image = UIImage(cgImage: cut)
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Room photos on disk, decoded once and normalised to "up" orientation so pins line up.
@MainActor
enum RoomPhotos {
    private static let cache = NSCache<NSString, UIImage>()

    /// Drops cached photos (after a room is deleted).
    static func purge() { cache.removeAllObjects() }

    static func image(roomId: UUID, index: Int, revision: Int) -> UIImage? {
        let key = "\(roomId)-\(index)-\(revision)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let raw = UIImage(contentsOfFile: FileStore.roomPhotoURL(roomId, index: index).path(percentEncoded: false)) else { return nil }
        let image = raw.normalisedUp()
        cache.setObject(image, forKey: key)
        return image
    }

    /// Indices of the photos this phone has for a room.
    static func available(_ room: Room, revision: Int) -> [Int] {
        (0..<min(room.photoCount, Room.maxPhotos)).filter { image(roomId: room.id, index: $0, revision: revision) != nil }
    }
}

extension UIImage {
    /// Redrawn so `imageOrientation` is `.up`, at 1 pixel per point (and no bigger than `maxSide`).
    /// The renderer's default scale is the screen's (3×), which made a 12 MP photo a ~440 MB bitmap.
    func normalisedUp(maxSide: CGFloat? = nil) -> UIImage {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let shrink = maxSide.map { min(1, $0 / max(pixels.width, pixels.height)) } ?? 1
        guard imageOrientation != .up || shrink < 1 else { return self }
        let target = CGSize(width: (pixels.width * shrink).rounded(), height: (pixels.height * shrink).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }

    /// JPEG for upload, scaled so the longest side is at most `Size.photoUpload` pixels. Pixels
    /// only: no location, camera or other metadata.
    func jpegForUpload(maxSide: CGFloat = Size.photoUpload) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        guard let cgImage = resized.cgImage else { return nil }
        return PhotoMetadata.encodeJPEG(cgImage)
    }
}

/// Keeps location and other personal metadata out of saved room photos.
enum PhotoMetadata {
    static let quality: CGFloat = 0.78

    /// Metadata groups that can say where, when or with what a photo was taken: any of these at all.
    private static let personal: [CFString] = [
        kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
        kCGImagePropertyMakerAppleDictionary, kCGImagePropertyExifAuxDictionary,
    ]
    /// EXIF and TIFF keys ImageIO writes on its own that describe only the pixels. Any other key
    /// in those groups (date, camera, lens, software, serial number…) counts as personal.
    private static let pixelOnly = Set([
        kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension, kCGImagePropertyExifColorSpace,
        kCGImagePropertyTIFFOrientation, kCGImagePropertyTIFFXResolution, kCGImagePropertyTIFFYResolution,
        kCGImagePropertyTIFFResolutionUnit,
    ].map { $0 as String })

    /// A JPEG of `cgImage` with no metadata: only the pixels (and their colour profile) are written.
    static func encodeJPEG(_ cgImage: CGImage, quality: CGFloat = quality) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The personal metadata `jpeg` carries, by group (empty when it's clean).
    static func personalGroups(in jpeg: Data) -> [String] {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [] }
        var found = personal.filter { properties[$0] != nil }.map { $0 as String }
        for group in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary] {
            let keys = (properties[group] as? [String: Any])?.keys.filter { !pixelOnly.contains($0) } ?? []
            if !keys.isEmpty { found.append("\(group) (\(keys.sorted().joined(separator: ", ")))") }
        }
        return found
    }

    /// `jpeg` without location or other personal metadata, or nil if that couldn't be done (so a
    /// photo carrying it is never saved). Already-clean photos come back as they are; otherwise the
    /// pixels are re-encoded on their own, with any EXIF rotation drawn in.
    static func stripped(_ jpeg: Data) -> Data? {
        let groups = personalGroups(in: jpeg)
        guard !groups.isEmpty else { return jpeg }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(Size.photoUpload),
        ]
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let clean = encodeJPEG(cgImage), personalGroups(in: clean).isEmpty else {
            detectLog.error("[Photo] couldn’t remove \(groups.joined(separator: ", "), privacy: .public); not saved")
            return nil
        }
        detectLog.notice("[Photo] removed \(groups.joined(separator: ", "), privacy: .public) before saving")
        return clean
    }
}
