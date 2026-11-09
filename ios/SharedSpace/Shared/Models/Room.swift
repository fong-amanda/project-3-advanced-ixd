import Foundation
import SwiftData

/// A room being changed. Local cache of the `rooms` table.
///
/// Coordinates used everywhere (items, designs, AR): centimetres, x to the right and z toward
/// the front, measured from the room's back-left corner; y is up. Scanned rooms are rotated so
/// their longest wall runs along x (see Scanning/RoomFrame).
@Model
final class Room {
    @Attribute(.unique) var id: UUID
    var code: String
    var name: String
    var currentUse: String
    var futureUse: String
    var widthCm: Int
    var lengthCm: Int
    var heightCm: Int

    var hostUserId: UUID
    var hostName: String
    var guestUserId: UUID?
    var guestName: String?
    var invitedAt: Date?
    var guestJoinedAt: Date?

    /// 0 = never scanned. Bumped on every rescan.
    var scanVersion: Int
    /// Storage path of the shared simplified geometry (walls, doors, windows) for other devices.
    var geometryPath: String?

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    // Sync bookkeeping (local only)
    var needsUpload: Bool
    var existsRemotely: Bool

    @Relationship(deleteRule: .cascade, inverse: \Item.room) var items: [Item] = []
    @Relationship(deleteRule: .cascade, inverse: \Design.room) var designs: [Design] = []

    init(
        id: UUID = UUID(), code: String, name: String, currentUse: String, futureUse: String,
        widthCm: Int = 340, lengthCm: Int = 380, heightCm: Int = 250,
        hostUserId: UUID, hostName: String
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.currentUse = currentUse
        self.futureUse = futureUse
        self.widthCm = widthCm
        self.lengthCm = lengthCm
        self.heightCm = heightCm
        self.hostUserId = hostUserId
        self.hostName = hostName
        self.scanVersion = 0
        self.createdAt = .now
        self.updatedAt = .now
        self.needsUpload = true
        self.existsRemotely = false
    }

    // MARK: - Convenience

    var liveItems: [Item] {
        items.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var liveDesigns: [Design] {
        designs.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func role(of userId: UUID) -> Role {
        userId == hostUserId ? .host : .guest
    }

    var hasGuest: Bool { !(guestName ?? "").isEmpty }
    var guestHasJoined: Bool { guestUserId != nil }
    var isScanned: Bool { scanVersion > 0 }

    /// Display name for a role, falling back sensibly when the guest hasn't been named.
    func name(of role: Role) -> String {
        switch role {
        case .host: hostName.isEmpty ? "Host" : hostName
        case .guest: (guestName ?? "").isEmpty ? "Guest" : (guestName ?? "")
        }
    }

    var transformLine: String {
        [currentUse, futureUse].filter { !$0.isEmpty }.joined(separator: " → ")
    }

    var floorAreaM2: Double { Double(widthCm * lengthCm) / 10_000 }
}

enum RoomCode {
    private static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    /// Five characters, no look-alikes (no I, L, O, 0, 1).
    static func make() -> String {
        String((0..<5).map { _ in alphabet.randomElement()! })
    }

    static func normalize(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(5))
    }
}
