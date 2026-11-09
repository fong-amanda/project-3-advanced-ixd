import Foundation
import RoomPlan
import simd

/// What a RoomPlan scan gives the app, already in room coordinates (cm, x right, z toward the
/// front, measured from the back-left corner; the longest wall runs along x).
struct ScanResult {
    struct Object: Identifiable {
        let id: UUID           // RoomPlan's identifier, kept as Item.scanObjectId
        let category: ItemCategory
        let name: String
        let w: Double, d: Double, h: Double
        let x: Double, z: Double
        let yawDeg: Double
    }

    var shape: RoomShape
    var heightCm: Double
    var objects: [Object]
}

enum ScanImporter {
    /// Converts a processed CapturedRoom. Walls become the outline (corners joined end to end),
    /// doors, windows and openings are placed on their nearest wall, and objects become things.
    static func convert(_ room: CapturedRoom) -> ScanResult? {
        let walls = room.walls.map { segment(of: $0) }
        guard walls.count >= 3 else { return nil }

        // Turn the room so its longest wall runs along x.
        let longest = walls.max { length($0) < length($1) }!
        let angle = -atan2(Double(longest.b.y - longest.a.y), Double(longest.b.x - longest.a.x))
        let rotate = { (p: SIMD2<Double>) in
            SIMD2(p.x * cos(angle) - p.y * sin(angle), p.x * sin(angle) + p.y * cos(angle))
        }

        var corners = outline(walls.map { (a: rotate($0.a.d), b: rotate($0.b.d)) })
        if corners.count < 3 { corners = boundingBox(walls.flatMap { [rotate($0.a.d), rotate($0.b.d)] }) }

        // Shift so the back-left corner is at (0, 0); metres to cm.
        let minX = corners.map(\.x).min()!, minZ = corners.map(\.y).min()!
        let toRoom = { (p: SIMD2<Double>) in SIMD2((p.x - minX) * 100, (p.y - minZ) * 100) }
        var shape = RoomShape(corners: corners.map { let p = toRoom($0); return .init(x: p.x.rounded(), z: p.y.rounded()) }, openings: [])
        if shape.winding < 0 { shape.corners.reverse() }

        let surfaces: [(CapturedRoom.Surface, RoomShape.Opening.Kind)] =
            room.doors.map { ($0, .door) } + room.openings.map { ($0, .door) } + room.windows.map { ($0, .window) }
        for (surface, kind) in surfaces {
            let c = toRoom(rotate(position(surface.transform)))
            let near = shape.nearestEdge(x: c.x, z: c.y)
            shape.openings.append(.init(kind: kind, edge: near.edge, position: near.position,
                                        width: (Double(surface.dimensions.x) * 100).rounded()))
        }

        let height = (room.walls.map { Double($0.dimensions.y) }.max() ?? 2.5) * 100
        let objects = room.objects.map { o -> ScanResult.Object in
            let c = toRoom(rotate(position(o.transform)))
            let category = map(o.category)
            let yaw = (atan2(Double(o.transform.columns.0.z), Double(o.transform.columns.0.x)) + angle) * 180 / .pi
            return ScanResult.Object(id: o.identifier, category: category, name: category.label,
                                     w: Double(o.dimensions.x) * 100, d: Double(o.dimensions.z) * 100, h: Double(o.dimensions.y) * 100,
                                     x: c.x.rounded(), z: c.y.rounded(), yawDeg: (yaw / 90).rounded() * 90)
        }
        return ScanResult(shape: shape, heightCm: height.rounded(), objects: objects)
    }

    // MARK: Geometry

    private struct Segment {
        let a: SIMD2<Float>
        let b: SIMD2<Float>
    }

    /// A wall's two ends on the floor (x, z in metres).
    private static func segment(of wall: CapturedRoom.Surface) -> Segment {
        let t = wall.transform
        let centre = SIMD2(t.columns.3.x, t.columns.3.z)
        let along = simd_normalize(SIMD2(t.columns.0.x, t.columns.0.z))
        let half = wall.dimensions.x / 2
        return Segment(a: centre - along * half, b: centre + along * half)
    }

    private static func length(_ s: Segment) -> Float { simd_distance(s.a, s.b) }

    private static func position(_ t: simd_float4x4) -> SIMD2<Double> { SIMD2(Double(t.columns.3.x), Double(t.columns.3.z)) }

    /// Joins walls end to end into a closed outline. Returns [] when they don't form a loop.
    private static func outline(_ walls: [(a: SIMD2<Double>, b: SIMD2<Double>)]) -> [SIMD2<Double>] {
        var remaining = walls
        var chain = [remaining[0].a, remaining[0].b]
        remaining.removeFirst()
        let tolerance = 0.35   // metres: RoomPlan's wall ends rarely meet exactly
        while !remaining.isEmpty {
            let end = chain.last!
            guard let (i, flip) = remaining.enumerated().compactMap({ (i, w) -> (Int, Bool, Double)? in
                let da = simd_distance(end, w.a), db = simd_distance(end, w.b)
                return min(da, db) < tolerance ? (i, db < da, min(da, db)) : nil
            }).min(by: { $0.2 < $1.2 }).map({ ($0.0, $0.1) }) else { return [] }
            let w = remaining.remove(at: i)
            chain.append(flip ? w.a : w.b)
        }
        guard simd_distance(chain.first!, chain.last!) < tolerance else { return [] }
        chain.removeLast()
        // Corners where both walls meet: average nearby points away.
        return chain
    }

    private static func boundingBox(_ points: [SIMD2<Double>]) -> [SIMD2<Double>] {
        let xs = points.map(\.x), zs = points.map(\.y)
        let (x0, x1, z0, z1) = (xs.min()!, xs.max()!, zs.min()!, zs.max()!)
        return [SIMD2(x0, z0), SIMD2(x1, z0), SIMD2(x1, z1), SIMD2(x0, z1)]
    }

    private static func map(_ c: CapturedRoom.Object.Category) -> ItemCategory {
        switch c {
        case .bed: .bed
        case .sofa: .sofa
        case .chair: .chair
        case .table: .table
        case .storage: .cabinet
        case .television: .television
        case .refrigerator, .stove, .oven, .dishwasher, .washerDryer, .sink: .appliance
        case .toilet, .bathtub, .fireplace, .stairs: .other
        @unknown default: .other
        }
    }
}

private extension SIMD2 where Scalar == Float {
    /// To Double precision.
    var d: SIMD2<Double> { SIMD2<Double>(Double(x), Double(y)) }
}
