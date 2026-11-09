import Foundation
import SwiftData

/// One redesign option ("Option A"). Up to three per room. Local cache of `designs`.
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

    @Relationship(deleteRule: .cascade, inverse: \DesignPlacement.design)
    var placements: [DesignPlacement] = []

    static let maxPerRoom = 3

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
