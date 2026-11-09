import Foundation
import SwiftData

/// One thing in a room. Shared by Sort (decisions) and Redesign (position, size).
/// Local cache of the `items` table.
@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var roomId: UUID
    var room: Room?

    var name: String
    var categoryRaw: String
    var sourceRaw: String
    /// RoomPlan's `CapturedRoom.Object.identifier` when this came from a scan.
    var scanObjectId: UUID?

    // Where it physically is today (room coordinates, cm / degrees).
    var widthCm: Double
    var depthCm: Double
    var heightCm: Double
    var xCm: Double
    var yCm: Double
    var zCm: Double
    var yawDeg: Double

    // Sort
    var ownerRaw: String
    var statusRaw: String
    var moveDestination: String?
    var decidedByRaw: String?
    var decidedAt: Date?
    var suggestionRaw: String?
    var suggestedByRaw: String?
    var suggestedAt: Date?
    var note: String
    var noteByRaw: String?
    var pickupDate: Date?
    /// Storage path ("<room>/items/<item>.jpg"). The local copy lives in FileStore.
    var photoPath: String?

    // Ask: one person asks the other what should happen to this thing.
    var askByRaw: String? = nil
    var askToRaw: String? = nil
    var askedAt: Date? = nil

    // Numbered pin on one of the room photos (fractions of the photo's width and height).
    var pinX: Double? = nil
    var pinY: Double? = nil
    /// Which room photo the pin is on (0 = the first).
    var pinPhoto: Int = 0

    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var needsUpload: Bool

    init(
        id: UUID = UUID(), room: Room, name: String, category: ItemCategory, source: ItemSource,
        size: (w: Double, d: Double, h: Double)? = nil,
        position: (x: Double, y: Double, z: Double) = (0, 0, 0), yawDeg: Double = 0,
        scanObjectId: UUID? = nil, sortOrder: Int
    ) {
        let s = size ?? category.defaultSize
        self.id = id
        self.roomId = room.id
        self.room = room
        self.name = name
        self.categoryRaw = category.rawValue
        self.sourceRaw = source.rawValue
        self.scanObjectId = scanObjectId
        self.widthCm = s.w
        self.depthCm = s.d
        self.heightCm = s.h
        self.xCm = position.x
        self.yCm = position.y
        self.zCm = position.z
        self.yawDeg = yawDeg
        self.ownerRaw = Owner.unassigned.rawValue
        self.statusRaw = ItemStatus.undecided.rawValue
        self.note = ""
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.updatedAt = .now
        self.needsUpload = true
    }

    // MARK: - Typed accessors

    var category: ItemCategory {
        get { ItemCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var source: ItemSource { ItemSource(rawValue: sourceRaw) ?? .manual }

    var owner: Owner {
        get { Owner(rawValue: ownerRaw) ?? .unassigned }
        set { ownerRaw = newValue.rawValue }
    }

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .undecided }
        set { statusRaw = newValue.rawValue }
    }

    var decidedBy: Role? {
        get { decidedByRaw.flatMap(Role.init(rawValue:)) }
        set { decidedByRaw = newValue?.rawValue }
    }

    var suggestion: ItemStatus? {
        get { suggestionRaw.flatMap(ItemStatus.init(rawValue:)) }
        set { suggestionRaw = newValue?.rawValue }
    }

    var suggestedBy: Role? {
        get { suggestedByRaw.flatMap(Role.init(rawValue:)) }
        set { suggestedByRaw = newValue?.rawValue }
    }

    var noteBy: Role? {
        get { noteByRaw.flatMap(Role.init(rawValue:)) }
        set { noteByRaw = newValue?.rawValue }
    }

    var askBy: Role? {
        get { askByRaw.flatMap(Role.init(rawValue:)) }
        set { askByRaw = newValue?.rawValue }
    }

    var askTo: Role? {
        get { askToRaw.flatMap(Role.init(rawValue:)) }
        set { askToRaw = newValue?.rawValue }
    }

    /// Where the pin sits on room photo `photo`, if it has one there.
    func pin(on photo: Int) -> CGPoint? {
        guard let x = pinX, let y = pinY, pinPhoto == photo else { return nil }
        return CGPoint(x: x, y: y)
    }

    var hasPin: Bool { pinX != nil && pinY != nil }

    var isDecided: Bool { status != .undecided }
}

extension Item {
    /// Live (not deleted) items of one room, in list order. Use with @Query.
    static func live(in roomId: UUID) -> FetchDescriptor<Item> {
        FetchDescriptor(predicate: #Predicate { $0.roomId == roomId && $0.deletedAt == nil },
                        sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
    }
}
