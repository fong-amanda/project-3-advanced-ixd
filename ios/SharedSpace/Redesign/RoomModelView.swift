import RealityKit
import SwiftUI

/// The room in 3D, as a dollhouse: the floor from the room's outline, walls (the back and left
/// walls full height, the others cut low so you can see in), doors and windows, and every thing
/// as a block of its real size. Drag to orbit, pinch to zoom, tap a thing to select it.
///
/// Things leaving the room are see-through (or left out, in the plan); pieces placed in a plan
/// are drawn in the highlight colour.
struct RoomModelView: View {
    let room: Room
    let entries: [PlanEntry]
    var showGhosts = true
    var selectedId: UUID?
    var onSelect: ((UUID?) -> Void)?

    var body: some View {
        let scene = RoomScene(shape: room.shape, height: Double(room.heightCm), entries: entries,
                              showGhosts: showGhosts, selectedId: selectedId)
        RealityView { content in
            content.camera = .virtual
            content.add(scene.build())
            content.add(scene.camera())
        } update: { content in
            // Snapshot first: removing while iterating the live collection crashes.
            let old = content.entities.filter { $0.name == RoomScene.rootName }
            for entity in old { content.remove(entity) }
            content.add(scene.build())
        }
        .realityViewCameraControls(.orbit)
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            var e: Entity? = value.entity
            while let current = e, UUID(uuidString: current.name) == nil { e = current.parent }
            let id = e.flatMap { UUID(uuidString: $0.name) }
            onSelect?(id == selectedId ? nil : id)
        })
        .background(Color.stage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("3D view of the room. Drag to look around.")
        .accessibilityValue(entries.filter { !$0.isGhost }.map(\.name).joined(separator: ", "))
    }
}

/// Builds the RealityKit entities for one moment of the room.
private struct RoomScene {
    static let rootName = "room-root"

    let shape: RoomShape
    let height: Double
    let entries: [PlanEntry]
    let showGhosts: Bool
    let selectedId: UUID?

    private static let wallThickness: Float = 0.08
    private static let lipHeight: Float = 0.06
    private static let ghostOpacity: Float = 0.22

    /// Looks at the room from the front right, high enough to see over the low walls.
    @MainActor
    func camera() -> Entity {
        let b = shape.bounds
        let span = Float(max(b.maxX, b.maxZ) / 100)
        let distance = span * 1.9 + 1.2
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 40
        cam.look(at: [0, 0.4, 0], from: [distance * 0.55, distance * 0.75, distance * 0.65], relativeTo: nil)
        return cam
    }

    @MainActor
    func build() -> Entity {
        let root = Entity()
        root.name = Self.rootName
        let b = shape.bounds
        root.position = [Float(-b.maxX / 200), 0, Float(-b.maxZ / 200)]

        if let floor = floorEntity() { root.addChild(floor) }
        for e in shape.edges where e.length > 5 { root.addChild(wall(e)) }
        for o in shape.openings { if let entity = opening(o) { root.addChild(entity) } }
        for entry in entries where showGhosts || !entry.isGhost { root.addChild(thing(entry)) }

        let sun = DirectionalLight()
        sun.light.intensity = 2600
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 12, depthBias: 2)
        sun.look(at: .zero, from: [2.5, 4.5, 3], relativeTo: nil)
        root.addChild(sun)
        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.look(at: .zero, from: [-3, 3, -2], relativeTo: nil)
        root.addChild(fill)
        return root
    }

    // MARK: Pieces of the room

    @MainActor
    private func floorEntity() -> ModelEntity? {
        let triangles = shape.triangulated()
        guard !triangles.isEmpty else { return nil }
        var d = MeshDescriptor(name: "floor")
        d.positions = MeshBuffers.Positions(shape.corners.map { SIMD3(Float($0.x / 100), 0, Float($0.z / 100)) })
        // Each triangle wound so it faces up (seen from above).
        let c = shape.corners
        d.primitives = .triangles(triangles.flatMap { t -> [Int] in
            let (a, b, e) = (c[t.0], c[t.1], c[t.2])
            let up = (b.z - a.z) * (e.x - a.x) - (b.x - a.x) * (e.z - a.z)
            return up > 0 ? [t.0, t.1, t.2] : [t.0, t.2, t.1]
        }.map(UInt32.init))
        d.normals = MeshBuffers.Normals(Array(repeating: SIMD3<Float>(0, 1, 0), count: c.count))
        guard let mesh = try? MeshResource.generate(from: [d]) else { return nil }
        return ModelEntity(mesh: mesh, materials: [material(.roomFloor, roughness: 0.75)])
    }

    @MainActor
    private func wall(_ e: RoomShape.Edge) -> ModelEntity {
        let n = shape.inwardNormal(e)
        // Cutaway: walls you'd see through from the default camera (front-right) stay low.
        let full = n.z > 0.5 || n.x > 0.5
        let h = full ? Float(height / 100) : Self.lipHeight
        let len = Float(e.length / 100) + Self.wallThickness
        let wall = ModelEntity(mesh: .generateBox(size: [len, h, Self.wallThickness]), materials: [material(.roomWall, roughness: 0.95)])
        let mid = e.point(at: 0.5)
        wall.position = [Float(mid.x / 100 - n.x * 0.04), h / 2, Float(mid.z / 100 - n.z * 0.04)]
        wall.orientation = simd_quatf(angle: Float(-atan2(e.dz, e.dx)), axis: [0, 1, 0])
        return wall
    }

    /// Doors and windows as panels just inside full-height walls.
    @MainActor
    private func opening(_ o: RoomShape.Opening) -> ModelEntity? {
        guard let p = shape.placement(of: o) else { return nil }
        let n = shape.inwardNormal(p.edge)
        guard n.z > 0.5 || n.x > 0.5 else { return nil }
        let w = Float(p.width / 100)
        let isWindow = o.kind == .window
        let size: SIMD3<Float> = isWindow ? [w, 1.2, 0.02] : [w, 2.05, 0.03]
        let panel = ModelEntity(mesh: .generateBox(size: size),
                                materials: [material(isWindow ? .roomWindow : .roomDoor, roughness: isWindow ? 0.2 : 0.8)])
        panel.position = [Float(p.center.x / 100 + n.x * 0.01), isWindow ? 1.45 : 1.025, Float(p.center.z / 100 + n.z * 0.01)]
        panel.orientation = simd_quatf(angle: Float(-atan2(p.edge.dz, p.edge.dx)), axis: [0, 1, 0])
        return panel
    }

    @MainActor
    private func thing(_ entry: PlanEntry) -> Entity {
        let isPiece = entry.style == .newPiece
        let h = Float(max(entry.isFlat ? 1 : heightOf(entry), 1) / 100)
        let colour: Color = isPiece ? .highlight : .material(entry.colorHex)
        var mat: any RealityKit.Material = material(colour, roughness: 0.8)
        if entry.isGhost {
            var pbr = PhysicallyBasedMaterial()
            pbr.baseColor = .init(tint: UIColor(colour))
            pbr.blending = .transparent(opacity: .init(floatLiteral: Self.ghostOpacity))
            mat = pbr
        }
        let block = ModelEntity(mesh: .generateBox(size: [Float(entry.widthCm / 100), h, Float(entry.depthCm / 100)],
                                                   cornerRadius: entry.isFlat ? 0 : 0.015),
                                materials: [mat])
        block.position = [Float(entry.xCm / 100), h / 2, Float(entry.zCm / 100)]
        block.orientation = simd_quatf(angle: Float(-entry.yawDeg * .pi / 180), axis: [0, 1, 0])
        block.name = entry.id.uuidString
        if !entry.isGhost {
            block.components.set(InputTargetComponent())
            block.generateCollisionShapes(recursive: false)
        }
        if entry.id == selectedId {
            // A flat accent frame on the floor around the selected thing.
            let ring = ModelEntity(mesh: .generateBox(size: [Float(entry.widthCm / 100) + 0.08, 0.004, Float(entry.depthCm / 100) + 0.08]),
                                   materials: [UnlitMaterial(color: UIColor(Color.accent))])
            ring.position = [0, -h / 2 + 0.003, 0]
            block.addChild(ring)
        }
        if entry.problem != nil {
            let warn = ModelEntity(mesh: .generateBox(size: [Float(entry.widthCm / 100) + 0.06, 0.004, Float(entry.depthCm / 100) + 0.06]),
                                   materials: [UnlitMaterial(color: UIColor(Color.danger))])
            warn.position = [0, -h / 2 + 0.002, 0]
            block.addChild(warn)
        }
        return block
    }

    /// Plan entries carry footprints only; heights come from the item or piece's kind.
    private func heightOf(_ entry: PlanEntry) -> Double { entry.heightCm ?? 75 }

    private func material(_ colour: Color, roughness: Float) -> SimpleMaterial {
        SimpleMaterial(color: UIColor(colour), roughness: .init(floatLiteral: roughness), isMetallic: false)
    }
}

extension RoomShape {
    /// Triangles (corner indices) covering the floor, by ear clipping.
    func triangulated() -> [(Int, Int, Int)] {
        var idx = Array(corners.indices)
        guard idx.count >= 3 else { return [] }
        let w = winding
        func cross(_ a: Int, _ b: Int, _ c: Int) -> Double {
            let p = corners[a], q = corners[b], r = corners[c]
            return ((q.x - p.x) * (r.z - p.z) - (q.z - p.z) * (r.x - p.x)) * w
        }
        func inside(_ p: Int, _ a: Int, _ b: Int, _ c: Int) -> Bool {
            cross(a, b, p) > 0 && cross(b, c, p) > 0 && cross(c, a, p) > 0
        }
        var out: [(Int, Int, Int)] = []
        var guardCount = 0
        while idx.count > 3, guardCount < 1000 {
            guardCount += 1
            var clipped = false
            for i in idx.indices {
                let a = idx[(i + idx.count - 1) % idx.count], b = idx[i], c = idx[(i + 1) % idx.count]
                guard cross(a, b, c) > 0 else { continue }
                if idx.contains(where: { $0 != a && $0 != b && $0 != c && inside($0, a, b, c) }) { continue }
                out.append((a, b, c))
                idx.remove(at: i)
                clipped = true
                break
            }
            if !clipped { break }
        }
        if idx.count == 3 { out.append((idx[0], idx[1], idx[2])) }
        return out
    }
}
