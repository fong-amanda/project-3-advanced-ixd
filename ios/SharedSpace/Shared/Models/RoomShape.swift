import Foundation

/// A room's floor outline (any polygon) with its doors and windows.
///
/// Corners are in room coordinates (cm), never negative; the room's width and length are the
/// largest x and z. Openings sit on a wall (edge i runs from corner i to corner i+1) at a fraction
/// along it. Rooms without a stored shape are plain rectangles.
struct RoomShape: Codable, Equatable, Sendable {
    struct Corner: Codable, Equatable, Sendable {
        var x: Double
        var z: Double
    }

    struct Opening: Codable, Equatable, Identifiable, Sendable {
        enum Kind: String, Codable, Sendable { case door, window }
        var id = UUID()
        var kind: Kind
        var edge: Int
        /// 0…1 along the wall, at the opening's centre.
        var position: Double
        var width: Double
        /// Doors: swing into the room (true) or out.
        var swingsIn = true
        /// Doors: hinge at the wall's end (true) or its start.
        var hingeAtEnd = false
    }

    var corners: [Corner]
    var openings: [Opening]

    static let defaultDoorWidth = 90.0
    static let defaultWindowWidth = 120.0
    static let doorWidthRange = 70.0...120.0
    static let windowWidthRange = 40.0...300.0
    static let snap = 10.0

    // MARK: Presets

    enum Preset: String, CaseIterable, Identifiable {
        case rectangle, lShape, alcove, angled
        var id: String { rawValue }
        var label: String {
            switch self {
            case .rectangle: "Rectangle"
            case .lShape: "L-shape"
            case .alcove: "Alcove"
            case .angled: "Angled corner"
            }
        }
    }

    static func preset(_ p: Preset, width W: Double, length L: Double) -> RoomShape {
        let s = { (v: Double) in (v / snap).rounded() * snap }
        let pts: [(Double, Double)]
        switch p {
        case .rectangle: pts = [(0, 0), (W, 0), (W, L), (0, L)]
        case .lShape:
            let cw = s(W * 0.4), cl = s(L * 0.4)
            pts = [(0, 0), (W, 0), (W, L - cl), (W - cw, L - cl), (W - cw, L), (0, L)]
        case .alcove:
            let a = s(W * 0.3), b = s(W * 0.7), n = s(L * 0.7)
            pts = [(0, 0), (W, 0), (W, n), (b, n), (b, L), (a, L), (a, n), (0, n)]
        case .angled:
            let c = s(min(W, L) * 0.3)
            pts = [(0, 0), (W, 0), (W, L - c), (W - c, L), (0, L)]
        }
        var shape = RoomShape(corners: pts.map { Corner(x: $0.0, z: $0.1) }, openings: [])
        shape.openings = shape.defaultOpenings()
        return shape
    }

    static func rectangle(width: Double, length: Double) -> RoomShape { preset(.rectangle, width: width, length: length) }

    /// Which preset this is, if any (for highlighting the chip).
    func matchingPreset() -> Preset? {
        let b = bounds
        return Preset.allCases.first { RoomShape.preset($0, width: b.maxX, length: b.maxZ).corners == corners }
    }

    // MARK: Measurements

    var bounds: (maxX: Double, maxZ: Double) {
        (corners.map(\.x).max() ?? 0, corners.map(\.z).max() ?? 0)
    }

    var area: Double {
        var s = 0.0
        for i in corners.indices {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            s += a.x * b.z - b.x * a.z
        }
        return abs(s) / 2
    }

    var isRectangle: Bool { matchingPreset() == .rectangle }

    struct Edge {
        let index: Int
        let a: Corner
        let b: Corner
        var dx: Double { b.x - a.x }
        var dz: Double { b.z - a.z }
        var length: Double { hypot(dx, dz) }
        func point(at t: Double) -> (x: Double, z: Double) { (a.x + dx * t, a.z + dz * t) }
    }

    var edges: [Edge] {
        corners.indices.map { Edge(index: $0, a: corners[$0], b: corners[($0 + 1) % corners.count]) }
    }

    /// +1 when corners run clockwise on screen (z down), −1 otherwise. Used to find "inside".
    var winding: Double {
        var s = 0.0
        for e in edges { s += e.a.x * e.b.z - e.b.x * e.a.z }
        return s > 0 ? 1 : -1
    }

    /// Unit vector pointing into the room from an edge.
    func inwardNormal(_ e: Edge) -> (x: Double, z: Double) {
        let len = max(e.length, 0.001)
        return (-winding * e.dz / len, winding * e.dx / len)
    }

    func contains(x: Double, z: Double) -> Bool {
        var inside = false
        var j = corners.count - 1
        for i in corners.indices {
            let a = corners[i], b = corners[j]
            if (a.z > z) != (b.z > z), x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// True when a footprint is fully on the floor (checked on a 5×5 grid, like the prototype).
    func contains(_ r: FloorRect) -> Bool {
        let inset = min(1.5, r.w / 4, r.d / 4)
        for a in 0...4 {
            for b in 0...4 {
                let x = r.x + inset + (r.w - 2 * inset) * Double(a) / 4
                let z = r.z + inset + (r.d - 2 * inset) * Double(b) / 4
                if !contains(x: x, z: z) { return false }
            }
        }
        return true
    }

    /// Two walls cross each other (the outline is invalid).
    var selfIntersects: Bool {
        let e = edges
        func orient(_ p: Corner, _ q: Corner, _ r: Corner) -> Double { (q.x - p.x) * (r.z - p.z) - (q.z - p.z) * (r.x - p.x) }
        func cross(_ a: Edge, _ b: Edge) -> Bool {
            (orient(a.a, a.b, b.a) > 0) != (orient(a.a, a.b, b.b) > 0) && (orient(b.a, b.b, a.a) > 0) != (orient(b.a, b.b, a.b) > 0)
        }
        for i in e.indices {
            for j in e.indices where j > i + 1 && !(i == 0 && j == e.count - 1) {
                if cross(e[i], e[j]) { return true }
            }
        }
        return false
    }

    // MARK: Openings

    /// Where an opening sits (clamped so it fits on its wall).
    func placement(of o: Opening) -> (center: (x: Double, z: Double), along: (x: Double, z: Double), width: Double, edge: Edge)? {
        guard !corners.isEmpty else { return nil }
        let e = edges[((o.edge % corners.count) + corners.count) % corners.count]
        let len = e.length
        guard len > 1 else { return nil }
        let w = min(o.width, max(30, len - 20))
        let half = w / 2 + 10
        let t = len > 2 * half ? min(max(o.position, half / len), 1 - half / len) : 0.5
        return (e.point(at: t), (e.dx / len, e.dz / len), w, e)
    }

    /// The nearest wall to a point, and how far along it (snapped to 10 cm).
    func nearestEdge(x: Double, z: Double) -> (edge: Int, position: Double) {
        var best = (d: Double.infinity, edge: 0, t: 0.5)
        for e in edges {
            let l2 = max(e.dx * e.dx + e.dz * e.dz, 1)
            let t = min(max(((x - e.a.x) * e.dx + (z - e.a.z) * e.dz) / l2, 0), 1)
            let p = e.point(at: t)
            let d = hypot(x - p.x, z - p.z)
            if d < best.d { best = (d, e.index, t) }
        }
        let len = edges[best.edge].length
        return (best.edge, (best.t * len / RoomShape.snap).rounded() * RoomShape.snap / max(len, 1))
    }

    /// A window on the longest back wall and a door on the longest left wall, like the prototype.
    func defaultOpenings() -> [Opening] {
        let candidates = edges.filter { $0.length >= 130 }
        let back = candidates.filter { inwardNormal($0).z > 0.7 }.max { $0.length < $1.length }
            ?? edges.max { $0.length < $1.length }
        let left = edges.filter { $0.index != back?.index && inwardNormal($0).x > 0.7 && $0.length >= 140 }.max { $0.length < $1.length }
            ?? edges.filter { $0.index != back?.index }.max { $0.length < $1.length }
        var result: [Opening] = []
        if let back { result.append(Opening(kind: .window, edge: back.index, position: back.dx >= 0 ? 0.62 : 0.38, width: Self.defaultWindowWidth)) }
        if let left { result.append(Opening(kind: .door, edge: left.index, position: left.dz > 0 ? 0.82 : 0.18, width: Self.defaultDoorWidth)) }
        return result
    }

    /// The wall with the most free room for a new opening.
    func bestEdgeForNewOpening() -> (edge: Int, position: Double) {
        let counts = edges.map { e in openings.filter { $0.edge == e.index }.count }
        let pick = edges.max { a, b in
            (a.length - Double(counts[a.index]) * 400 - (a.length < 120 ? 1e5 : 0)) <
                (b.length - Double(counts[b.index]) * 400 - (b.length < 120 ? 1e5 : 0))
        } ?? edges[0]
        let n = counts[pick.index]
        return (pick.index, n == 0 ? 0.5 : 0.25 + 0.5 * Double(n % 2))
    }

    // MARK: Editing

    /// Adds a corner in the middle of a wall; openings on that wall keep their place.
    mutating func insertCorner(onEdge k: Int) -> Int {
        let e = edges[k]
        let mid = Corner(x: ((e.a.x + e.b.x) / 2 / Self.snap).rounded() * Self.snap,
                         z: ((e.a.z + e.b.z) / 2 / Self.snap).rounded() * Self.snap)
        corners.insert(mid, at: k + 1)
        for i in openings.indices {
            if openings[i].edge > k { openings[i].edge += 1 }
            else if openings[i].edge == k {
                if openings[i].position < 0.5 { openings[i].position *= 2 }
                else { openings[i].edge = k + 1; openings[i].position = (openings[i].position - 0.5) * 2 }
            }
        }
        return k + 1
    }

    /// Removes a corner (rooms keep at least three); openings move to the merged wall.
    mutating func removeCorner(_ i: Int) {
        guard corners.count > 3 else { return }
        let n = corners.count
        for j in openings.indices {
            let e = openings[j].edge, f = openings[j].position
            if i == 0 {
                if e == n - 1 { openings[j].edge = n - 2; openings[j].position = f * 0.5 }
                else if e == 0 { openings[j].edge = n - 2; openings[j].position = 0.5 + f * 0.5 }
                else { openings[j].edge = e - 1 }
            } else if e == i - 1 { openings[j].position = f * 0.5 }
            else if e == i { openings[j].edge = i - 1; openings[j].position = 0.5 + f * 0.5 }
            else if e > i { openings[j].edge = e - 1 }
        }
        corners.remove(at: i)
    }

    /// Moves a corner, snapped to 10 cm and kept at or above zero.
    mutating func moveCorner(_ i: Int, x: Double, z: Double) {
        corners[i] = Corner(x: max(0, (x / Self.snap).rounded() * Self.snap), z: max(0, (z / Self.snap).rounded() * Self.snap))
    }

    /// Stretches the outline to a new width and length.
    func scaled(toWidth W: Double, length L: Double) -> RoomShape {
        let b = bounds
        guard b.maxX > 0, b.maxZ > 0 else { return .rectangle(width: W, length: L) }
        var copy = self
        copy.corners = corners.map { Corner(x: ($0.x * W / b.maxX).rounded(), z: ($0.z * L / b.maxZ).rounded()) }
        return copy
    }
}

extension Room {
    /// The floor outline; a rectangle of the room's size when none is stored.
    var shape: RoomShape {
        get {
            if let data = shapeData, let s = try? JSONDecoder().decode(RoomShape.self, from: data), s.corners.count >= 3 {
                return s
            }
            return .rectangle(width: Double(widthCm), length: Double(lengthCm))
        }
        set {
            let b = newValue.bounds
            widthCm = Int(b.maxX.rounded())
            lengthCm = Int(b.maxZ.rounded())
            // A plain rectangle with the default openings is stored too, so the door and window positions sync.
            shapeData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Changes width and length, stretching the outline to match.
    func resize(width: Double, length: Double) {
        shape = shape.scaled(toWidth: width, length: length)
    }
}
