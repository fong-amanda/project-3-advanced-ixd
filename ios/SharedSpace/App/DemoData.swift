#if DEBUG
import SwiftUI
import UIKit

/// Debug builds only. Launch with `-demoRoom` to get the prototype's sample room
/// (Linda turning Alex's old room into a study, with Alex's things still in it).
/// Add `-demoTab room|sort|plan|people` to open a specific tab, and `-demoAsGuest` to see Alex's view.
///
/// For the accessibility audit (UITests/AccessibilityAuditTests): `-forceDark` / `-forceLight`,
/// `-demoReset` (a fresh demo room with a sample photo and pins), `-demoItemSheet` (opens the
/// first item's decision sheet), `-demoNewRoom photos` (New room on its photo step) and
/// `-a11yCheck` (opens the Accessibility check screen).
@MainActor
enum DemoData {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-demoRoom") }

    /// `-demoAsGuest`: open the demo room previewing Alex's view.
    static var asGuest: Bool { ProcessInfo.processInfo.arguments.contains("-demoAsGuest") }

    /// `-demo3D`: open Room plan in the 3D view.
    static var show3D: Bool { ProcessInfo.processInfo.arguments.contains("-demo3D") }

    private static var args: [String] { ProcessInfo.processInfo.arguments }

    /// `-forceDark` / `-forceLight`.
    static var colorScheme: ColorScheme? {
        args.contains("-forceDark") ? .dark : args.contains("-forceLight") ? .light : nil
    }
    static var reset: Bool { args.contains("-demoReset") }
    static var openItemSheet: Bool { args.contains("-demoItemSheet") }
    static var openAccessibilityCheck: Bool { args.contains("-a11yCheck") }
    /// `-demoNewRoom photos`: the step New room opens on.
    static var newRoomStep: String? {
        guard let i = args.firstIndex(of: "-demoNewRoom"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var requestedTab: RoomTab? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoTab"), i + 1 < args.count else { return nil }
        return ["room": .room, "items": .items, "sort": .items, "plan": .plan, "people": .people][args[i + 1]]
    }

    /// Returns the demo room, creating it the first time.
    static func room(sync: SyncEngine) -> Room {
        if let existing = sync.fetchAll(Room.self).first(where: { $0.name == "Alex’s old room" && $0.deletedAt == nil }) {
            if !reset { return existing }
            existing.deletedAt = .now
            sync.save(existing)
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
            if let pin = samplePins[s.0] {
                item.pinX = pin.x; item.pinY = pin.y; item.pinPhoto = 0
            }
            sync.insert(item)
            sync.save(item)
        }
        if let jpeg = samplePhoto().jpegForUpload() { sync.savePhoto(jpeg, index: 0, of: room) }
        return room
    }

    /// Pins on the sample photo. Desk and Guitar are deliberately close, to show pins being nudged
    /// apart so their 44-point tap areas don't overlap.
    private static let samplePins: [String: CGPoint] = [
        "Bed": CGPoint(x: 0.24, y: 0.68), "Desk": CGPoint(x: 0.58, y: 0.56), "Guitar": CGPoint(x: 0.62, y: 0.58),
        "Bookshelf": CGPoint(x: 0.86, y: 0.36), "Boxes of clothes": CGPoint(x: 0.82, y: 0.82),
    ]

    /// A drawn stand-in for a room photo (walls, floor and furniture shapes), so the demo room has
    /// pins to look at and tap without needing a real photo.
    static func samplePhoto() -> UIImage {
        let size = CGSize(width: 1600, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            func fill(_ hex: UInt32, _ r: CGRect) { UIColor(hex: hex).setFill(); c.fill(r) }
            fill(0xE9E2D6, CGRect(origin: .zero, size: size))                      // wall
            fill(0xB58E66, CGRect(x: 0, y: 760, width: 1600, height: 440))         // floor
            fill(0xF4F1EA, CGRect(x: 120, y: 120, width: 360, height: 300))        // window
            fill(0x8FA7B5, CGRect(x: 140, y: 140, width: 320, height: 260))
            fill(0x7C8C74, CGRect(x: 120, y: 700, width: 540, height: 240))        // bed
            fill(0xEDE6DA, CGRect(x: 120, y: 660, width: 160, height: 80))
            fill(0x6E5440, CGRect(x: 780, y: 600, width: 400, height: 40))         // desk
            fill(0x6E5440, CGRect(x: 800, y: 640, width: 24, height: 200))
            fill(0x6E5440, CGRect(x: 1136, y: 640, width: 24, height: 200))
            fill(0x9C6B3C, CGRect(x: 960, y: 520, width: 60, height: 240))         // guitar
            fill(0x5B4636, CGRect(x: 1300, y: 160, width: 200, height: 620))       // bookshelf
            fill(0xC9B79E, CGRect(x: 1220, y: 900, width: 220, height: 160))       // boxes
        }
    }
}
#endif
