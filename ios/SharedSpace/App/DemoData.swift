#if DEBUG
import Foundation

/// Debug builds only. Launch with `-demoRoom` to get the prototype's sample room
/// (Maya's home office becoming a guest room, with some of Sam's things in it).
/// Add `-demoTab home|sort|redesign|people` to open a specific tab, and `-demoAsGuest` to see Sam's view.
@MainActor
enum DemoData {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-demoRoom") }

    /// `-demoAsGuest`: open the demo room previewing Sam's view.
    static var asGuest: Bool { ProcessInfo.processInfo.arguments.contains("-demoAsGuest") }

    static var requestedTab: AppTab? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoTab"), i + 1 < args.count else { return nil }
        return ["home": .home, "sort": .sort, "redesign": .redesign, "people": .people][args[i + 1]]
    }

    /// Returns the demo room, creating it the first time.
    static func room(sync: SyncEngine) -> Room {
        if let existing = sync.fetchAll(Room.self).first(where: { $0.name == "Upstairs office" && $0.deletedAt == nil }) {
            return existing
        }
        if Identity.name.isEmpty { Identity.name = "Maya" }
        let room = sync.createRoom(name: "Upstairs office", currentUse: "Home office", futureUse: "Guest room",
                                   hostName: Identity.name)
        room.guestName = "Sam"
        sync.save(room)

        // name, category, w, d, h, x, z, yaw, owner, decision (from the prototype's sample room)
        let sample: [(String, ItemCategory, Double, Double, Double, Double, Double, Double, Owner, ItemStatus)] = [
            ("Desk", .desk, 140, 70, 75, 95, 40, 0, .host, .letGo),
            ("Office chair", .chair, 62, 62, 100, 95, 112, 180, .host, .sendToOwner),
            ("Filing cabinet", .cabinet, 45, 60, 100, 196, 32, 0, .host, .letGo),
            ("Monstera plant", .plant, 34, 34, 90, 237, 22, 0, .host, .undecided),
            ("Bookshelf", .bookshelf, 76, 30, 200, 296, 17, 0, .shared, .undecided),
            ("Floor lamp", .lamp, 35, 35, 160, 318, 62, 0, .host, .keep),
            ("Armchair", .armchair, 82, 82, 90, 280, 230, 270, .shared, .undecided),
            ("Blue rug", .rug, 200, 140, 1, 175, 245, 0, .host, .keep),
            ("Exercise bike", .exerciseBike, 110, 55, 130, 60, 290, 90, .guest, .undecided),
            ("Moving boxes", .boxes, 70, 50, 80, 300, 345, 0, .guest, .undecided),
            ("Guitar", .guitar, 40, 15, 100, 14, 175, 90, .guest, .undecided),
        ]
        for (i, s) in sample.enumerated() {
            let item = Item(room: room, name: s.0, category: s.1, source: .manual, size: (s.2, s.3, s.4),
                            position: (s.5, 0, s.6), yawDeg: s.7, sortOrder: i)
            item.owner = s.8
            if s.9 != .undecided {
                item.status = s.9
                item.decidedBy = .host
                item.decidedAt = .now
            }
            sync.insert(item)
            sync.save(item)
        }
        return room
    }
}
#endif
