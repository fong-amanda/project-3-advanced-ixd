import RealityKit
import SwiftUI

/// The room in 3D, as a dollhouse: the floor from the room's outline, walls (the back and left
/// walls full height, the others cut low so you can see in), doors and windows, and every thing
/// as a block of its real size. Drag to orbit, pinch to zoom, tap a thing to select it.
///
/// Things leaving the room are see-through and carry a label saying where they're going (or are
/// left out, in the plan); pieces placed in a plan are drawn in the sage tint.
///
/// Nothing in the scene animates: changes (a decision, showing hidden things) rebuild it at once.
/// The camera only moves while you drag. With Reduce Motion on, the system orbit controls (which
/// keep spinning after you let go) are replaced by a plain drag-to-turn and pinch-to-zoom that stop
/// the moment your finger does: no inertia, no damping, no auto-rotation.
struct RoomModelView: View {
    let room: Room
    let entries: [PlanEntry]
    var showGhosts = true
    var selectedId: UUID?
    var onSelect: ((UUID?) -> Void)?

    private var ghosts: [PlanEntry] { showGhosts ? entries.filter(\.isGhost) : [] }

    /// The view's size, for sizing tap volumes (measured, so the RealityView stays the root view).
    @State private var viewSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Reduce Motion camera: angles in radians and a zoom factor, changed only by your fingers.
    @State private var orbit = Orbit()
    @State private var orbitAtStart: Orbit?

    struct Orbit: Equatable {
        var yaw: Float = atan2(0.55, 0.65)
        var pitch: Float = atan2(0.75, (0.55 * 0.55 + 0.65 * 0.65).squareRoot())
        var zoom: Float = 1
    }

    var body: some View {
        let scene = RoomScene(shape: room.shape, height: Double(room.heightCm), entries: entries,
                              showGhosts: showGhosts, selectedId: selectedId, viewSize: viewSize)
        RealityView { content in
            content.camera = .virtual
            content.add(scene.build())
            content.add(scene.camera())
        } update: { content in
            // Snapshot first: removing while iterating the live collection crashes.
            let old = content.entities.filter { $0.name == RoomScene.rootName }
            for entity in old { content.remove(entity) }
            content.add(scene.build())
            if reduceMotion, let cam = content.entities.first(where: { $0.name == RoomScene.cameraName }) {
                scene.place(cam, orbit: orbit)
            }
        }
        .realityViewCameraControls(reduceMotion ? .none : .orbit)
        .simultaneousGesture(orbitDrag, including: reduceMotion ? .all : .subviews)
        .simultaneousGesture(orbitPinch, including: reduceMotion ? .all : .subviews)
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            var e: Entity? = value.entity
            while let current = e, UUID(uuidString: current.name) == nil { e = current.parent }
            let id = e.flatMap { UUID(uuidString: $0.name) }
            onSelect?(id == selectedId ? nil : id)
        })
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        // VoiceOver reads `accessibilityLayer` instead: an accessibility container on a RealityView stops it drawing.
        .accessibilityHidden(true)
        .background(Color.stage)
        .overlay(alignment: .bottomLeading) {
            if !ghosts.isEmpty {
                Label("See-through things are leaving the room", systemImage: "eye.slash")
                    .font(.detailStrong)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                    .background(Color.surface, in: Capsule())
                    .padding(Space.m)
                    .accessibilityHidden(true)
            }
        }
        .overlay { accessibilityLayer }
    }

    /// Reduce Motion: turn the room by dragging; it stops exactly when the finger does.
    private var orbitDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = orbitAtStart ?? orbit
                if orbitAtStart == nil { orbitAtStart = orbit }
                var next = start
                next.yaw = start.yaw - Float(value.translation.width) * 0.008
                next.pitch = min(max(start.pitch + Float(value.translation.height) * 0.006, 0.15), 1.35)
                orbit = next
            }
            .onEnded { _ in orbitAtStart = nil }
    }

    private var orbitPinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = orbitAtStart ?? orbit
                if orbitAtStart == nil { orbitAtStart = orbit }
                orbit.zoom = min(max(start.zoom / Float(value.magnification), 0.45), 2.2)
            }
            .onEnded { _ in orbitAtStart = nil }
    }

    /// An invisible layer that lists each thing for VoiceOver, with where it stands
    /// ("Guitar, going to Sam"); things still in the room can be selected from it.
    private var accessibilityLayer: some View {
        Color.clear
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("3D view of the room")
        .accessibilityChildren {
            // Each thing, with where it stands ("Guitar, going to Sam"), selectable when it's still here.
            ForEach(entries.filter { !$0.isGhost || showGhosts }) { entry in
                if onSelect != nil && !entry.isGhost {
                    Rectangle()
                        .accessibilityLabel(entry.spokenName)
                        .accessibilityValue(entry.problem ?? "")
                        .accessibilityAddTraits(entry.id == selectedId ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { onSelect?(entry.id == selectedId ? nil : entry.id) }
                } else {
                    Rectangle()
                        .accessibilityLabel(entry.isGhost ? "\(entry.spokenName), shown see-through" : entry.spokenName)
                }
            }
        }
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
    var viewSize: CGSize = .zero

    private static let wallThickness: Float = 0.08
    private static let lipHeight: Float = 0.06
    private static let ghostOpacity: Float = 0.22

    private static let fieldOfView: Float = 40
    private var cameraDistance: Float { Float(max(shape.bounds.maxX, shape.bounds.maxZ) / 100) * 1.9 + 1.2 }

    static let cameraName = "room-camera"

    /// Looks at the room from the front right, high enough to see over the low walls.
    @MainActor
    func camera() -> Entity {
        let distance = cameraDistance
        let cam = PerspectiveCamera()
        cam.name = Self.cameraName
        cam.camera.fieldOfViewInDegrees = Self.fieldOfView
        cam.look(at: [0, 0.4, 0], from: [distance * 0.55, distance * 0.75, distance * 0.65], relativeTo: nil)
        return cam
    }

    /// Reduce Motion camera: placed straight from the angles, with nothing easing in between.
    @MainActor
    func place(_ cam: Entity, orbit: RoomModelView.Orbit) {
        let r = cameraDistance * (0.55 * 0.55 + 0.75 * 0.75 + 0.65 * 0.65).squareRoot() * orbit.zoom
        let from = SIMD3<Float>(r * cos(orbit.pitch) * sin(orbit.yaw), r * sin(orbit.pitch), r * cos(orbit.pitch) * cos(orbit.yaw))
        cam.look(at: [0, 0.4, 0], from: from, relativeTo: nil)
    }

    /// How many metres 44 points cover at the starting camera distance, so small things can be
    /// given a tap volume at least that big.
    private var minimumHitSize: Float {
        let side = Float(min(viewSize.width, viewSize.height))
        guard side > 0 else { return 0.3 }
        let visible = 2 * cameraDistance * tan(Self.fieldOfView * .pi / 360)
        return Float(Size.tapTarget) * visible / side
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
        let colour: Color = isPiece ? .tintSage : .material(entry.colorHex)
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
            // A tap volume of at least 44 × 44 points, even for small things like a lamp.
            let m = minimumHitSize
            let size: SIMD3<Float> = [max(Float(entry.widthCm / 100), m), max(h, m), max(Float(entry.depthCm / 100), m)]
            block.components.set(InputTargetComponent())
            block.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        } else {
            // Leaving: see-through and labelled with where it's going, never just tinted.
            let tag = label("\(entry.name) · \(entry.statusText ?? "leaving")")
            tag.position = [0, h / 2 + 0.18, 0]
            block.addChild(tag)
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

    /// A small white label that always faces the camera.
    @MainActor
    private func label(_ text: String) -> Entity {
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.001,
                                             font: .systemFont(ofSize: 0.15, weight: .semibold),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
        let b = mesh.bounds
        let words = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: UIColor(Color.onPhotoText))])
        words.position = [-b.center.x, -b.center.y, 0.003]
        let plate = ModelEntity(mesh: .generatePlane(width: b.extents.x + 0.12, height: b.extents.y + 0.08, cornerRadius: 0.04),
                                materials: [UnlitMaterial(color: UIColor(Color.photoBadge))])
        let holder = Entity()
        holder.addChild(plate)
        holder.addChild(words)
        holder.components.set(BillboardComponent())
        return holder
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
