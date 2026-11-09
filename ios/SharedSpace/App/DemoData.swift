#if DEBUG
import Foundation

/// Debug builds only. Launch with `-demoRoom` to get the prototype's sample room
/// (Linda turning Alex's old room into a study, with Alex's things still in it).
/// Add `-demoTab items|plan` to open a specific tab, and `-demoAsGuest` to see Alex's view.
@MainActor
enum DemoData {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-demoRoom") }

    /// `-demoAsGuest`: open the demo room previewing Alex's view.
    static var asGuest: Bool { ProcessInfo.processInfo.arguments.contains("-demoAsGuest") }

    /// `-demo3D`: open Room plan in the 3D view.
    static var show3D: Bool { ProcessInfo.processInfo.arguments.contains("-demo3D") }

    static var requestedTab: RoomTab? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoTab"), i + 1 < args.count else { return nil }
        return ["items": .items, "plan": .plan][args[i + 1]]
    }

    /// Returns the demo room, creating it the first time.
    static func room(sync: SyncEngine) -> Room {
        if let existing = sync.fetchAll(Room.self).first(where: { $0.name == "Alex’s old room" && $0.deletedAt == nil }) {
            return existing
        }
        if Identity.name.isEmpty { Identity.name = "Linda" }
        let room = sync.createRoom(name: "Alex’s old room", currentUse: "Kid’s old room", futureUse: "Study",
                                   hostName: Identity.name)
        room.guestName = "Alex"
        room.measured = true
        room.shape = .rectangle(width: 340, length: 380)
        sync.save(room)

        // name, category, w, d, h, x, z, yaw, owner, decision (the prototype's SAMPLE_ITEMS and seedExample)
        let sample: [(String, ItemCategory, Double, Double, Double, Double, Double, Double, Owner, ItemStatus)] = [
            ("Bed", .bed, 100, 205, 90, 60, 150, 0, .guest, .undecided),
            ("Desk", .desk, 140, 70, 75, 190, 45, 0, .guest, .undecided),
            ("Bookshelf", .bookshelf, 80, 30, 190, 300, 17, 0, .guest, .keep),
            ("Boxes of clothes", .boxes, 70, 50, 80, 305, 250, 0, .guest, .sendToOwner),
            ("Guitar", .guitar, 40, 15, 100, 330, 105, 90, .guest, .undecided),
            ("Trophies", .other, 60, 25, 35, 300, 52, 0, .guest, .undecided),
            ("Rug", .rug, 160, 110, 1, 190, 260, 0, .host, .keep),
        ]
        for (i, s) in sample.enumerated() {
            let item = Item(room: room, name: s.0, category: s.1, source: .manual, size: (s.2, s.3, s.4),
                            position: (s.5, 0, s.6), yawDeg: s.7, sortOrder: i)
            item.owner = s.8
            if s.9 != .undecided {
                item.status = s.9
                item.decidedBy = s.8 == .host ? .host : .guest
                item.decidedAt = .now
            }
            sync.insert(item)
            sync.save(item)
        }
        return room
    }
}
#endif
