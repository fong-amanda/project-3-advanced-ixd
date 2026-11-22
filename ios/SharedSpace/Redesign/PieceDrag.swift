import Foundation

/// Rules for where a placed piece can go, shared by placing, dragging in 3D and the plan's
/// problem notes, so they always agree.
enum PlacementCheck {
    /// "Goes through a wall", "Overlaps the desk", or nil when the spot is fine.
    /// `others` are the things it can bump into: staying furniture and the other placed pieces.
    static func problem(_ f: FloorRect, room: Room, others: [PlanEntry]) -> String? {
        if f.x < -1 || f.z < -1 || f.maxX > Double(room.widthCm) + 1 || f.maxZ > Double(room.lengthCm) + 1
            || !room.shape.contains(f) {
            return "Goes through a wall"
        }
        if let hit = others.first(where: { !$0.isGhost && !$0.isFlat && f.overlaps($0.footprint, padding: 2) }) {
            return "Overlaps the \(hit.name.lowercased())"
        }
        return nil
    }

    /// Rotation snaps to 15° steps (so 0°, 90°, 180° and 270° are always reachable).
    static func snapYaw(_ deg: Double) -> Double {
        let s = (deg / 15).rounded() * 15
        return (s.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Keeps a dragged piece on the floor and inside the walls, and pulls it flush against a wall
    /// when it comes within `snap` cm of one.
    static func constrain(x: Double, z: Double, w: Double, d: Double, yaw: Double, room: Room,
                          snap: Double = 8) -> (x: Double, z: Double) {
        let W = Double(room.widthCm), L = Double(room.lengthCm)
        var f = RoomGeometry.footprint(x: x, z: z, w: w, d: d, yawDeg: yaw)
        var cx = x, cz = z
        // Inside the room's bounding box.
        if f.x < 0 { cx -= f.x }
        if f.z < 0 { cz -= f.z }
        if f.maxX > W { cx -= f.maxX - W }
        if f.maxZ > L { cz -= f.maxZ - L }
        f = RoomGeometry.footprint(x: cx, z: cz, w: w, d: d, yawDeg: yaw)
        // Flush against a wall when it's close.
        if f.x < snap { cx -= f.x } else if W - f.maxX < snap { cx += W - f.maxX }
        if f.z < snap { cz -= f.z } else if L - f.maxZ < snap { cz += L - f.maxZ }
        return (cx.rounded(), cz.rounded())
    }

    /// "1′ 8″ from the left wall, 4′ 2″ from the back wall": for VoiceOver.
    static func spokenPosition(_ e: PlanEntry, units: UnitSystem) -> String {
        let f = e.footprint
        return "\(units.roomLength(max(f.x, 0))) from the left wall, \(units.roomLength(max(f.z, 0))) from the back wall"
    }
}
