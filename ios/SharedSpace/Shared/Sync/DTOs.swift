import Foundation

// Wire formats for the Supabase tables. Property names map to snake_case columns automatically
// (see JSONCoding). Each DTO converts to and from its SwiftData model.

// MARK: - Rooms

/// Full row, used when a room is first created and when reading.
struct RoomDTO: Codable {
    var id: UUID
    var code: String
    var name: String
    var currentUse: String
    var futureUse: String
    var widthCm: Int
    var lengthCm: Int
    var heightCm: Int
    var hostUserId: UUID
    var hostName: String
    @NullCodable var guestUserId: UUID?
    @NullCodable var guestName: String?
    @NullCodable var invitedAt: Date?
    @NullCodable var guestJoinedAt: Date?
    var scanVersion: Int
    @NullCodable var geometryPath: String?
    var createdAt: Date
    var updatedAt: Date
    @NullCodable var deletedAt: Date?

    init(_ r: Room) {
        id = r.id; code = r.code; name = r.name; currentUse = r.currentUse; futureUse = r.futureUse
        widthCm = r.widthCm; lengthCm = r.lengthCm; heightCm = r.heightCm
        hostUserId = r.hostUserId; hostName = r.hostName
        guestUserId = r.guestUserId; guestName = r.guestName
        invitedAt = r.invitedAt; guestJoinedAt = r.guestJoinedAt
        scanVersion = r.scanVersion; geometryPath = r.geometryPath
        createdAt = r.createdAt; updatedAt = r.updatedAt; deletedAt = r.deletedAt
    }
}

/// The columns the host may change after creation. Deliberately leaves out guest_user_id and
/// guest_joined_at so a host edit can never undo a guest joining at the same moment.
struct RoomPatchDTO: Encodable {
    var name: String
    var currentUse: String
    var futureUse: String
    var widthCm: Int
    var lengthCm: Int
    var heightCm: Int
    var hostName: String
    @NullCodable var guestName: String?
    @NullCodable var invitedAt: Date?
    var scanVersion: Int
    @NullCodable var geometryPath: String?
    var updatedAt: Date
    @NullCodable var deletedAt: Date?

    init(_ r: Room) {
        name = r.name; currentUse = r.currentUse; futureUse = r.futureUse
        widthCm = r.widthCm; lengthCm = r.lengthCm; heightCm = r.heightCm
        hostName = r.hostName; guestName = r.guestName; invitedAt = r.invitedAt
        scanVersion = r.scanVersion; geometryPath = r.geometryPath
        updatedAt = r.updatedAt; deletedAt = r.deletedAt
    }
}

extension Room {
    func apply(_ d: RoomDTO) {
        code = d.code; name = d.name; currentUse = d.currentUse; futureUse = d.futureUse
        widthCm = d.widthCm; lengthCm = d.lengthCm; heightCm = d.heightCm
        hostUserId = d.hostUserId; hostName = d.hostName
        guestUserId = d.guestUserId; guestName = d.guestName
        invitedAt = d.invitedAt; guestJoinedAt = d.guestJoinedAt
        scanVersion = d.scanVersion; geometryPath = d.geometryPath
        createdAt = d.createdAt; updatedAt = d.updatedAt; deletedAt = d.deletedAt
        needsUpload = false
        existsRemotely = true
    }

    convenience init(_ d: RoomDTO) {
        self.init(id: d.id, code: d.code, name: d.name, currentUse: d.currentUse, futureUse: d.futureUse,
                  hostUserId: d.hostUserId, hostName: d.hostName)
        apply(d)
    }
}

// MARK: - Items

struct ItemDTO: Codable {
    var id: UUID
    var roomId: UUID
    var name: String
    var category: String
    var source: String
    @NullCodable var scanObjectId: UUID?
    var widthCm: Double
    var depthCm: Double
    var heightCm: Double
    var xCm: Double
    var yCm: Double
    var zCm: Double
    var yawDeg: Double
    var owner: String
    var status: String
    @NullCodable var moveDestination: String?
    @NullCodable var decidedBy: String?
    @NullCodable var decidedAt: Date?
    @NullCodable var suggestion: String?
    @NullCodable var suggestedBy: String?
    @NullCodable var suggestedAt: Date?
    var note: String
    @NullCodable var noteBy: String?
    @NullCodable var pickupDate: Date?
    @NullCodable var photoPath: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    @NullCodable var deletedAt: Date?

    init(_ i: Item) {
        id = i.id; roomId = i.roomId; name = i.name; category = i.categoryRaw; source = i.sourceRaw
        scanObjectId = i.scanObjectId
        widthCm = i.widthCm; depthCm = i.depthCm; heightCm = i.heightCm
        xCm = i.xCm; yCm = i.yCm; zCm = i.zCm; yawDeg = i.yawDeg
        owner = i.ownerRaw; status = i.statusRaw; moveDestination = i.moveDestination
        decidedBy = i.decidedByRaw; decidedAt = i.decidedAt
        suggestion = i.suggestionRaw; suggestedBy = i.suggestedByRaw; suggestedAt = i.suggestedAt
        note = i.note; noteBy = i.noteByRaw; pickupDate = i.pickupDate; photoPath = i.photoPath
        sortOrder = i.sortOrder; createdAt = i.createdAt; updatedAt = i.updatedAt; deletedAt = i.deletedAt
    }
}

extension Item {
    func apply(_ d: ItemDTO) {
        name = d.name; categoryRaw = d.category; sourceRaw = d.source; scanObjectId = d.scanObjectId
        widthCm = d.widthCm; depthCm = d.depthCm; heightCm = d.heightCm
        xCm = d.xCm; yCm = d.yCm; zCm = d.zCm; yawDeg = d.yawDeg
        ownerRaw = d.owner; statusRaw = d.status; moveDestination = d.moveDestination
        decidedByRaw = d.decidedBy; decidedAt = d.decidedAt
        suggestionRaw = d.suggestion; suggestedByRaw = d.suggestedBy; suggestedAt = d.suggestedAt
        note = d.note; noteByRaw = d.noteBy; pickupDate = d.pickupDate; photoPath = d.photoPath
        sortOrder = d.sortOrder; createdAt = d.createdAt; updatedAt = d.updatedAt; deletedAt = d.deletedAt
        needsUpload = false
    }

    convenience init(_ d: ItemDTO, room: Room) {
        self.init(id: d.id, room: room, name: d.name, category: ItemCategory(rawValue: d.category) ?? .other,
                  source: ItemSource(rawValue: d.source) ?? .manual, sortOrder: d.sortOrder)
        apply(d)
    }
}

// MARK: - Designs

struct DesignDTO: Codable {
    var id: UUID
    var roomId: UUID
    var name: String
    var sortOrder: Int
    var hostLikes: Bool
    var guestLikes: Bool
    var createdAt: Date
    var updatedAt: Date
    @NullCodable var deletedAt: Date?

    init(_ d: Design) {
        id = d.id; roomId = d.roomId; name = d.name; sortOrder = d.sortOrder
        hostLikes = d.hostLikes; guestLikes = d.guestLikes
        createdAt = d.createdAt; updatedAt = d.updatedAt; deletedAt = d.deletedAt
    }
}

/// What the host uploads for a design. Likes are left out: they change only through the
/// `set_design_like` function, so a host edit never clobbers the guest's like.
struct DesignUpsertDTO: Encodable {
    var id: UUID
    var roomId: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    @NullCodable var deletedAt: Date?

    init(_ d: Design) {
        id = d.id; roomId = d.roomId; name = d.name; sortOrder = d.sortOrder
        createdAt = d.createdAt; updatedAt = d.updatedAt; deletedAt = d.deletedAt
    }
}

extension Design {
    func apply(_ d: DesignDTO) {
        name = d.name; sortOrder = d.sortOrder; hostLikes = d.hostLikes; guestLikes = d.guestLikes
        createdAt = d.createdAt; updatedAt = d.updatedAt; deletedAt = d.deletedAt
        needsUpload = false
        existsRemotely = true
    }

    convenience init(_ d: DesignDTO, room: Room) {
        self.init(id: d.id, room: room, name: d.name, sortOrder: d.sortOrder)
        apply(d)
    }
}

struct PlacementDTO: Codable {
    var id: UUID
    var roomId: UUID
    var designId: UUID
    @NullCodable var itemId: UUID?
    @NullCodable var catalogId: String?
    var xCm: Double
    var zCm: Double
    var yawDeg: Double
    var hidden: Bool
    var updatedAt: Date
    @NullCodable var deletedAt: Date?

    init(_ p: DesignPlacement) {
        id = p.id; roomId = p.roomId; designId = p.designId; itemId = p.itemId; catalogId = p.catalogId
        xCm = p.xCm; zCm = p.zCm; yawDeg = p.yawDeg; hidden = p.hidden
        updatedAt = p.updatedAt; deletedAt = p.deletedAt
    }
}

extension DesignPlacement {
    func apply(_ d: PlacementDTO) {
        itemId = d.itemId; catalogId = d.catalogId
        xCm = d.xCm; zCm = d.zCm; yawDeg = d.yawDeg; hidden = d.hidden
        updatedAt = d.updatedAt; deletedAt = d.deletedAt
        needsUpload = false
    }

    convenience init(_ d: PlacementDTO, design: Design) {
        self.init(id: d.id, design: design, itemId: d.itemId, catalogId: d.catalogId,
                  xCm: d.xCm, zCm: d.zCm, yawDeg: d.yawDeg, hidden: d.hidden)
        apply(d)
    }
}

// MARK: - RPC results

struct RoomPeek: Decodable, Equatable {
    var id: UUID
    var name: String
    var futureUse: String
    var hostName: String
    var guestName: String?
    var isHost: Bool
}

/// Broadcast in the room's Realtime presence channel ("here now").
struct PresenceState: Codable {
    var userId: UUID
    var name: String
}
