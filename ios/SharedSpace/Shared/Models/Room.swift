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

    /// "ft" (feet and inches) or "cm". Only changes how sizes are shown; storage is always cm.
    var units: String = "ft"
    /// True once someone measured the room. Until then sizes are estimates and fit checks stay off.
    var measured: Bool = false
    /// Number of room photos (stored as <room>/photos/<n>.jpg). Up to three angles.
    var photoCount: Int = 0
    /// The plan version the host shared with the guest.
    var sharedDesignId: UUID? = nil
    /// The floor outline with doors and windows (JSON of RoomShape). nil = a plain rectangle.
    var shapeData: Data? = nil

    /// Room goals (at least one is on). Turning one off only hides it: items, decisions and layouts
    /// are kept and come back when it's turned on again. Existing rooms have both on.
    var sortEnabled: Bool = true
    var planEnabled: Bool = true

    /// Archived by the person on this phone only (each member archives for themselves; stored on
    /// their room_members row). Archived rooms keep everything and sit in "Archived" on Home.
    var archived: Bool = false
    /// The archive flag changed offline and still has to reach the server.
    var archiveNeedsUpload: Bool = false

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

    func isEnabled(_ goal: RoomGoal) -> Bool {
        switch goal {
        case .sort: sortEnabled
        case .plan: planEnabled
        }
    }

    var goals: [RoomGoal] { RoomGoal.allCases.filter(isEnabled) }

    /// True when Sort says this item leaves the room. With "Sort things" off, nothing leaves:
    /// the plan shows every item where it is and never mentions decisions.
    func leaves(_ item: Item) -> Bool { sortEnabled && item.status.leavesRoom }

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

    var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: units) ?? .feet }
        set { units = newValue.rawValue }
    }

    static let maxPhotos = 3
}

/// What a room is for. A room has one or both.
enum RoomGoal: String, CaseIterable, Identifiable, Sendable {
    case sort, plan

    var id: String { rawValue }

    /// On the goal cards ("Sort things").
    var title: String {
        switch self {
        case .sort: "Sort things"
        case .plan: "Plan the room"
        }
    }

    var detail: String {
        switch self {
        case .sort: "Decide what stays and what goes."
        case .plan: "Redesign the layout and furniture."
        }
    }

    /// On tags ("Sorting").
    var tag: String {
        switch self {
        case .sort: "Sorting"
        case .plan: "Planning"
        }
    }

    var symbol: String {
        switch self {
        case .sort: "checklist"
        case .plan: "cube"
        }
    }

    var tone: Tone {
        switch self {
        case .sort: .sage
        case .plan: .slate
        }
    }
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
