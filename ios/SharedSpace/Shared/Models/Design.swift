import Foundation
import SwiftData

/// One room plan version. Local cache of `designs`.
///
/// * The working plan ("Proposed layout") is unlocked and the host edits it.
/// * "Save a version" and "Share plan" make locked copies ("Version 2", "Shared 1"), which are
///   read-only snapshots. Rooms made before Nov 2026 may also have unlocked "Option A/B/C" plans.
/// * The guest reacts to the shared version: `guestLikes` means "Looks good", and
///   `reactionNote` holds their "One thing…" note.
///
/// A design stores only what it changes. A real item with no placement is shown where it
/// physically is, so a brand-new design is the room exactly as it is today. Sort decisions are
/// never copied into a design; Redesign reads `Item.status` live (see Redesign/DesignResolver).
@Model
final class Design {
    @Attribute(.unique) var id: UUID
    var roomId: UUID
    var room: Room?
    var name: String
    var sortOrder: Int
    var hostLikes: Bool
    var guestLikes: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var needsUpload: Bool
    var existsRemotely: Bool

    /// Saved versions are snapshots: nobody edits them, the host can continue from one.
    var locked: Bool = false
    /// The guest's "One thing…" note on this version (nil when they said it looks good).
    var reactionNote: String? = nil
    var reactionAt: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \DesignPlacement.design)
    var placements: [DesignPlacement] = []

    static let workingName = "Proposed layout"

    init(id: UUID = UUID(), room: Room, name: String, sortOrder: Int) {
        self.id = id
        self.roomId = room.id
        self.room = room
        self.name = name
        self.sortOrder = sortOrder
        self.hostLikes = false
        self.guestLikes = false
        self.createdAt = .now
        self.updatedAt = .now
        self.needsUpload = true
        self.existsRemotely = false
    }

    var livePlacements: [DesignPlacement] { placements.filter { $0.deletedAt == nil } }

    func likes(_ role: Role) -> Bool { role == .host ? hostLikes : guestLikes }
}

/// A change a design makes: a real item moved/rotated/hidden, or a new catalogue piece.
@Model
final class DesignPlacement {
    @Attribute(.unique) var id: UUID
    var roomId: UUID
    var designId: UUID
    var design: Design?
    /// Set when this moves/hides a real item.
    var itemId: UUID?
    /// Set when this is a new piece from the catalogue.
    var catalogId: String?
    var xCm: Double
    var zCm: Double
    var yawDeg: Double
    var hidden: Bool
    var updatedAt: Date
    var deletedAt: Date?
    var needsUpload: Bool

    init(
        id: UUID = UUID(), design: Design, itemId: UUID? = nil, catalogId: String? = nil,
        xCm: Double, zCm: Double, yawDeg: Double, hidden: Bool = false
    ) {
        precondition((itemId == nil) != (catalogId == nil), "A placement is either a real item or a catalogue piece")
        self.id = id
        self.roomId = design.roomId
        self.designId = design.id
        self.design = design
        self.itemId = itemId
        self.catalogId = catalogId
        self.xCm = xCm
        self.zCm = zCm
        self.yawDeg = yawDeg
        self.hidden = hidden
        self.updatedAt = .now
        self.needsUpload = true
    }

    var isNewPiece: Bool { catalogId != nil }
}

extension Design {
    /// Live designs of one room, in option order. Use with @Query.
    static func live(in roomId: UUID) -> FetchDescriptor<Design> {
        FetchDescriptor(predicate: #Predicate { $0.roomId == roomId && $0.deletedAt == nil },
                        sortBy: [SortDescriptor(\.sortOrder)])
    }
}
