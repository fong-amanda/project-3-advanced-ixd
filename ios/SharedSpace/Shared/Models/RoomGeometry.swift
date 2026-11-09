import Foundation

/// A rectangle on the floor, in room coordinates (cm). x/z is the top-left corner.
struct FloorRect: Equatable {
    var x: Double
    var z: Double
    var w: Double
    var d: Double

    var maxX: Double { x + w }
    var maxZ: Double { z + d }

    func overlaps(_ o: FloorRect, padding: Double = 0) -> Bool {
        x < o.maxX - padding && maxX - padding > o.x && z < o.maxZ - padding && maxZ - padding > o.z
    }
}

/// Floor-plan maths ported from the prototype, generalised to any rotation.
enum RoomGeometry {
    /// Axis-aligned bounding box of a w×d rectangle centred on (x, z) and turned by `yawDeg`.
    static func footprint(x: Double, z: Double, w: Double, d: Double, yawDeg: Double) -> FloorRect {
        let a = yawDeg * .pi / 180
        let bw = abs(w * cos(a)) + abs(d * sin(a))
        let bd = abs(w * sin(a)) + abs(d * cos(a))
        return FloorRect(x: x - bw / 2, z: z - bd / 2, w: bw, d: bd)
    }

    static func footprint(of item: Item) -> FloorRect {
        footprint(x: item.xCm, z: item.zCm, w: item.widthCm, d: item.depthCm, yawDeg: item.yawDeg)
    }

    /// Finds a free spot for a new w×d thing, preferring places along a wall.
    /// Returns the centre point. Falls back to the middle of the room when nothing fits.
    static func findSpot(w: Double, d: Double, avoiding obstacles: [FloorRect],
                         roomWidth W: Double, roomLength L: Double, inside shape: RoomShape? = nil) -> (x: Double, z: Double) {
        var best: (x: Double, z: Double, score: Double)?
        var z = d / 2 + 4
        while z <= L - d / 2 - 4 {
            var x = w / 2 + 4
            while x <= W - w / 2 - 4 {
                let r = FloorRect(x: x - w / 2, z: z - d / 2, w: w, d: d)
                if !obstacles.contains(where: { r.overlaps($0, padding: 1) }), shape?.contains(r) ?? true {
                    let wallDistance = min(r.x, r.z, W - r.maxX, L - r.maxZ)
                    let score = wallDistance + abs(z - L * 0.4) * 0.05
                    if best == nil || score < best!.score { best = (x, z, score) }
                }
                x += 10
            }
            z += 10
        }
        if let best { return (best.x, best.z) }
        // Nothing fits: the floor point nearest the middle.
        if let shape {
            var near: (x: Double, z: Double, d: Double)?
            for z in stride(from: 10.0, to: L, by: 10) {
                for x in stride(from: 10.0, to: W, by: 10) where shape.contains(x: x, z: z) {
                    let dist = hypot(x - W / 2, z - L / 2)
                    if near == nil || dist < near!.d { near = (x, z, dist) }
                }
            }
            if let near { return (near.x, near.z) }
        }
        return (W / 2, L / 2)
    }

    /// Obstacles for placement: every live item that stands on the floor.
    static func obstacles(_ items: [Item]) -> [FloorRect] {
        items.filter { !$0.category.isFlat }.map(footprint(of:))
    }
}
