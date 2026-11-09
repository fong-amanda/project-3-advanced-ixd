import SwiftUI

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
        .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        if item.photoPath != nil, let own = UIImage(contentsOfFile: FileStore.itemPhotoURL(roomId: item.roomId, itemId: item.id).path()) {
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

    static func image(roomId: UUID, index: Int, revision: Int) -> UIImage? {
        let key = "\(roomId)-\(index)-\(revision)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let raw = UIImage(contentsOfFile: FileStore.roomPhotoURL(roomId, index: index).path()) else { return nil }
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
    func normalisedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        return UIGraphicsImageRenderer(size: size).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// JPEG for upload, scaled so the longest side is at most `Size.photoUpload` pixels.
    func jpegForUpload(maxSide: CGFloat = Size.photoUpload) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.78)
    }
}
