import Foundation
import RoomPlan

@MainActor
enum ScanActions {
    /// Uses a scan for an existing room: replaces the outline and size, marks it measured, and
    /// adds the furniture found. Things found in an earlier scan (same RoomPlan id) are moved and
    /// resized instead of added twice; decisions and owners are never touched.
    static func apply(_ result: ScanResult, captured: CapturedRoom, to room: Room, items: [Item], sync: SyncEngine) {
        room.shape = result.shape
        room.heightCm = Int(result.heightCm)
        room.measured = true
        room.scanVersion += 1
        sync.save(room)
        save(captured, for: room.id)

        var order = (items.map(\.sortOrder).max() ?? -1) + 1
        let owner = SortActions.defaultOwner(in: room, items: items)
        for o in result.objects {
            if let existing = items.first(where: { $0.scanObjectId == o.id }) {
                existing.widthCm = o.w; existing.depthCm = o.d; existing.heightCm = o.h
                existing.xCm = o.x; existing.zCm = o.z; existing.yawDeg = o.yawDeg
                sync.save(existing)
            } else {
                let item = Item(room: room, name: o.name, category: o.category, source: .scanned,
                                size: (o.w, o.d, o.h), position: (o.x, 0, o.z), yawDeg: o.yawDeg,
                                scanObjectId: o.id, sortOrder: order)
                item.owner = owner
                order += 1
                sync.insert(item)
                sync.save(item)
            }
        }
    }

    /// Keeps RoomPlan's full result on this phone (for a 3D model or AR later).
    static func save(_ captured: CapturedRoom, for roomId: UUID) {
        if let data = try? JSONEncoder().encode(captured) {
            try? data.write(to: FileStore.capturedRoomURL(roomId), options: .atomic)
        }
    }
}
