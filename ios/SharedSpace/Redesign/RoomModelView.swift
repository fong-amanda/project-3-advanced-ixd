import RealityKit
import SwiftUI

/// The room in 3D, as a dollhouse: the floor from the room's outline, walls (the back and left
/// walls full height, the others cut low so you can see in), doors and windows, and every thing
/// as a block of its real size. Tap a thing to select it.
///
/// Gestures, so moving furniture and moving the camera never fight:
/// * one finger on a placed piece (when `onMovePiece` is set) slides it along the floor; it stays
///   inside the walls and snaps flush to a wall when close. Its outline turns red while it overlaps
///   something or crosses a wall, and a bar on the view says what;
/// * one finger on empty floor turns the room; pinch zooms;
/// * two-finger twist turns the selected piece in 15° steps (or the room, when nothing's selected).
/// The camera is always ours (no system orbit controls), so it never keeps spinning after you let go.
///
/// Things leaving the room are see-through and carry a label saying where they're going (or are
/// left out, in the plan); pieces placed in a plan are drawn in the sage tint.
struct RoomModelView: View {
    let room: Room
    let entries: [PlanEntry]
    var showGhosts = true
    var selectedId: UUID?
    var onSelect: ((UUID?) -> Void)?
    /// Pieces that can be dragged and twisted, and where they end up (x, z in cm, yaw in degrees).
    var movableIds: Set<UUID> = []
    var onMovePiece: ((UUID, Double, Double, Double) -> Void)?
    /// The piece that was just placed: drawn with a wider accent outline.
    var highlightId: UUID?

    private var ghosts: [PlanEntry] { showGhosts ? entries.filter(\.isGhost) : [] }

    /// The view's size, for sizing tap volumes and turning touches into floor points.
    @State private var viewSize: CGSize = .zero
    /// The camera: angles in radians and a zoom factor, changed only by your fingers.
    @State private var orbit = Orbit()
    @State private var orbitAtStart: Orbit?
    /// A piece being dragged or twisted, drawn there until it's let go and saved.
    @State private var moving: Moving?
    @State private var gesture: GestureMode = .none

    private enum GestureMode { case none, orbit, move, pinch, twist }

    struct Orbit: Equatable {
        var yaw: Float = atan2(0.55, 0.65)
        var pitch: Float = atan2(0.75, (0.55 * 0.55 + 0.65 * 0.65).squareRoot())
        var zoom: Float = 1
    }

    struct Moving: Equatable {
        let id: UUID
        var x: Double
        var z: Double
        var yaw: Double
        /// Where the finger grabbed it, relative to its centre (cm), so it doesn't jump.
        var grab: (dx: Double, dz: Double) = (0, 0)
        var startYaw: Double = 0
        static func == (a: Moving, b: Moving) -> Bool { a.id == b.id && a.x == b.x && a.z == b.z && a.yaw == b.yaw }
    }

    /// Entries as drawn: the moving piece where the finger has it.
    private var drawn: [PlanEntry] {
        guard let m = moving else { return entries }
        return entries.map { e in
            guard e.id == m.id else { return e }
            var e = e
            e.xCm = m.x; e.zCm = m.z; e.yawDeg = m.yaw
            e.problem = liveProblem(e)
            return e
        }
    }

    private func liveProblem(_ e: PlanEntry) -> String? {
        PlacementCheck.problem(e.footprint, room: room, others: entries.filter { $0.id != e.id })
    }

    var body: some View {
        // Read so the scene is rebuilt with real models once they've loaded.
        let _ = ModelCache.shared.revision
        let scene = RoomScene(shape: room.shape, height: Double(room.heightCm), entries: drawn,
                              showGhosts: showGhosts, selectedId: selectedId, highlightId: highlightId, viewSize: viewSize)
        RealityView { content in
            content.camera = .virtual
            content.add(scene.build())
            content.add(scene.camera())
        } update: { content in
            // Snapshot first: removing while iterating the live collection crashes.
            let old = content.entities.filter { $0.name == RoomScene.rootName }
            for entity in old { content.remove(entity) }
            content.add(scene.build())
            if let cam = content.entities.first(where: { $0.name == RoomScene.cameraName }) {
                scene.place(cam, orbit: orbit)
            }
        }
        .realityViewCameraControls(.none)
        .task(id: Set(entries.compactMap(\.model))) { await ModelCache.shared.preload(entries.compactMap(\.model)) }
        .gesture(dragGesture)
        .simultaneousGesture(pinchGesture)
        .simultaneousGesture(twistGesture)
        .simultaneousGesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
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
            if let m = moving, let e = drawn.first(where: { $0.id == m.id }) {
                movingBar(e)
            } else if !ghosts.isEmpty {
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
        #if DEBUG
        // UI tests: a 1-point marker where the selected piece appears, so they can drag it.
        .overlay(alignment: .topLeading) {
            if let id = selectedId, let e = drawn.first(where: { $0.id == id }), let p = screenPoint(e) {
                Color.clear.frame(width: 1, height: 1)
                    .position(p)
                    .accessibilityElement()
                    .accessibilityIdentifier("debug-selected-piece")
                    .accessibilityLabel("\(Int(e.xCm)),\(Int(e.zCm)),\(Int(e.yawDeg))")
            }
        }
        #endif
    }

    /// Where a thing's centre (at half its height) appears in the view: the inverse of `floorPoint`.
    private func screenPoint(_ e: PlanEntry) -> CGPoint? {
        guard viewSize.width > 0 else { return nil }
        let pose = RoomScene.cameraPose(shape: room.shape, orbit: orbit)
        let f = simd_normalize(pose.target - pose.from)
        let right = simd_normalize(simd_cross(f, [0, 1, 0]))
        let up = simd_cross(right, f)
        let b = room.shape.bounds
        let point = SIMD3<Float>(Float((e.xCm - b.maxX / 2) / 100), Float((e.isFlat ? 0 : (e.heightCm ?? 75) / 2) / 100),
                                 Float((e.zCm - b.maxZ / 2) / 100))
        let v = point - pose.from
        let depth = simd_dot(v, f)
        guard depth > 0 else { return nil }
        let t = tan(RoomScene.fieldOfView * .pi / 360), aspect = Float(viewSize.width / viewSize.height)
        let nx = simd_dot(v, right) / (depth * t * aspect), ny = simd_dot(v, up) / (depth * t)
        return CGPoint(x: CGFloat((nx + 1) / 2) * viewSize.width, y: CGFloat((1 - ny) / 2) * viewSize.height)
    }

    /// While dragging or twisting: the piece's name, size and whether the spot works.
    private func movingBar(_ e: PlanEntry) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(e.name).font(.bodyStrong).foregroundStyle(Color.textPrimary)
            Text("\(room.unitSystem.dims(e.widthCm, e.depthCm, e.heightCm ?? 0)) · \(Int(e.yawDeg))°")
                .font(.detail).foregroundStyle(Color.textSecondary)
            if let problem = e.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.detailStrong).foregroundStyle(Color.danger)
            } else {
                Label("Fits here", systemImage: "checkmark").font(.detailStrong).foregroundStyle(Color.keep)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .elevation(.floating)
        .padding(Space.m)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Gestures

    /// One finger: on a movable piece, move it; anywhere else, turn the room.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if gesture == .pinch || gesture == .twist { return }
                if gesture == .none {
                    if onMovePiece != nil, let (e, hit) = pieceUnder(value.startLocation) {
                        gesture = .move
                        moving = Moving(id: e.id, x: e.xCm, z: e.zCm, yaw: e.yawDeg, grab: (e.xCm - hit.x, e.zCm - hit.z))
                        if selectedId != e.id { onSelect?(e.id) }
                    } else {
                        gesture = .orbit
                        orbitAtStart = orbit
                    }
                }
                switch gesture {
                case .move:
                    guard var m = moving, let e = entries.first(where: { $0.id == m.id }),
                          let p = floorPoint(value.location, heightCm: (e.heightCm ?? 75) / 2) else { return }
                    let c = PlacementCheck.constrain(x: p.x + m.grab.dx, z: p.z + m.grab.dz, w: e.widthCm, d: e.depthCm,
                                                     yaw: m.yaw, room: room)
                    m.x = c.x; m.z = c.z
                    moving = m
                case .orbit:
                    let start = orbitAtStart ?? orbit
                    var next = start
                    next.yaw = start.yaw - Float(value.translation.width) * 0.008
                    next.pitch = min(max(start.pitch + Float(value.translation.height) * 0.006, 0.15), 1.35)
                    orbit = next
                default: break
                }
            }
            .onEnded { _ in
                if gesture == .move { commit() }
                if gesture == .move || gesture == .orbit { gesture = .none }
                orbitAtStart = nil
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if gesture == .move { moving = nil }   // a second finger: zoom instead of dropping it somewhere odd
                if gesture != .pinch { gesture = .pinch; orbitAtStart = orbit }
                orbit.zoom = min(max((orbitAtStart ?? orbit).zoom / Float(value.magnification), 0.45), 2.2)
            }
            .onEnded { _ in gesture = .none; orbitAtStart = nil }
    }

    /// Two-finger twist: turns the selected piece in 15° steps, or the room when nothing's selected.
    private var twistGesture: some Gesture {
        RotateGesture(minimumAngleDelta: .degrees(4))
            .onChanged { value in
                if let id = selectedId, movableIds.contains(id), onMovePiece != nil, let e = entries.first(where: { $0.id == id }) {
                    if moving == nil || moving?.id != id { moving = Moving(id: id, x: e.xCm, z: e.zCm, yaw: e.yawDeg, startYaw: e.yawDeg) }
                    gesture = .twist
                    guard var m = moving else { return }
                    // Twisting clockwise on screen turns it clockwise seen from above.
                    m.yaw = PlacementCheck.snapYaw(m.startYaw + value.rotation.degrees)
                    let c = PlacementCheck.constrain(x: m.x, z: m.z, w: e.widthCm, d: e.depthCm, yaw: m.yaw, room: room, snap: 0)
                    m.x = c.x; m.z = c.z
                    moving = m
                } else {
                    if gesture != .twist { gesture = .twist; orbitAtStart = orbit }
                    orbit.yaw = (orbitAtStart ?? orbit).yaw - Float(value.rotation.radians)
                }
            }
            .onEnded { _ in
                if moving != nil { commit() }
                gesture = .none; orbitAtStart = nil
            }
    }

    private func commit() {
        guard let m = moving else { return }
        onMovePiece?(m.id, m.x, m.z, m.yaw)
        // Keep drawing it where it was dropped until the saved plan catches up.
        DispatchQueue.main.async { moving = nil }
    }

    // MARK: Touch → floor

    /// The point on a horizontal plane `heightCm` above the floor under a touch, in room cm.
    private func floorPoint(_ point: CGPoint, heightCm: Double) -> (x: Double, z: Double)? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let pose = RoomScene.cameraPose(shape: room.shape, orbit: orbit)
        let f = simd_normalize(pose.target - pose.from)
        let right = simd_normalize(simd_cross(f, [0, 1, 0]))
        let up = simd_cross(right, f)
        let t = tan(RoomScene.fieldOfView * .pi / 360)
        let aspect = Float(viewSize.width / viewSize.height)
        let nx = Float(point.x / viewSize.width) * 2 - 1
        let ny = 1 - Float(point.y / viewSize.height) * 2
        let dir = simd_normalize(f + right * nx * t * aspect + up * ny * t)
        let planeY = Float(heightCm / 100)
        guard abs(dir.y) > 0.0001 else { return nil }
        let k = (planeY - pose.from.y) / dir.y
        guard k > 0 else { return nil }
        let hit = pose.from + dir * k
        let b = room.shape.bounds
        return (Double(hit.x) * 100 + b.maxX / 2, Double(hit.z) * 100 + b.maxZ / 2)
    }

    /// The movable piece under a touch (with a margin so small pieces are easy to grab), nearest first.
    private func pieceUnder(_ point: CGPoint) -> (PlanEntry, (x: Double, z: Double))? {
        let candidates = entries.filter { movableIds.contains($0.id) }
        var best: (PlanEntry, (x: Double, z: Double), Double)?
        for e in candidates {
            let h = e.isFlat ? 0 : (e.heightCm ?? 75) / 2
            guard let p = floorPoint(point, heightCm: h) else { continue }
            let f = e.footprint
            let margin = 15.0
            guard p.x >= f.x - margin, p.x <= f.maxX + margin, p.z >= f.z - margin, p.z <= f.maxZ + margin else { continue }
            let dist = hypot(p.x - e.xCm, p.z - e.zCm)
            if best == nil || dist < best!.2 { best = (e, p, dist) }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// An invisible layer that lists each thing for VoiceOver, with where it stands and where it is
    /// ("Armchair, placed in the plan. 1′ 8″ from the left wall, 4′ 2″ from the back wall").
    /// Placed pieces are moved with the arrow buttons on their bar (no dragging needed).
    private var accessibilityLayer: some View {
        Color.clear
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("3D view of the room")
        .accessibilityChildren {
            ForEach(entries.filter { !$0.isGhost || showGhosts }) { entry in
                let position = PlacementCheck.spokenPosition(entry, units: room.unitSystem)
                if onSelect != nil && !entry.isGhost {
                    Rectangle()
                        .accessibilityLabel(entry.spokenName)
                        .accessibilityValue([position, entry.problem].compactMap { $0 }.joined(separator: ". "))
                        .accessibilityHint(movableIds.contains(entry.id) ? "Select it, then use the move buttons below the view." : "")
                        .accessibilityAddTraits(entry.id == selectedId ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { onSelect?(entry.id == selectedId ? nil : entry.id) }
                } else {
                    Rectangle()
                        .accessibilityLabel(entry.isGhost ? "\(entry.spokenName), shown see-through" : entry.spokenName)
                        .accessibilityValue(position)
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
    var highlightId: UUID? = nil
    var viewSize: CGSize = .zero

    private static let wallThickness: Float = 0.08
    private static let lipHeight: Float = 0.06
    private static let ghostOpacity: Float = 0.22

    static let fieldOfView: Float = 40
    private var cameraDistance: Float { Self.cameraDistance(shape) }
    static func cameraDistance(_ shape: RoomShape) -> Float { Float(max(shape.bounds.maxX, shape.bounds.maxZ) / 100) * 1.9 + 1.2 }

    /// Where the camera is for an orbit, in scene metres (the room's centre is the origin).
    static func cameraPose(shape: RoomShape, orbit: RoomModelView.Orbit) -> (from: SIMD3<Float>, target: SIMD3<Float>) {
        let r = cameraDistance(shape) * (0.55 * 0.55 + 0.75 * 0.75 + 0.65 * 0.65).squareRoot() * orbit.zoom
        let from = SIMD3<Float>(r * cos(orbit.pitch) * sin(orbit.yaw), r * sin(orbit.pitch), r * cos(orbit.pitch) * cos(orbit.yaw))
        return (from, [0, 0.4, 0])
    }

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

    /// Placed straight from the angles, with nothing easing in between.
    @MainActor
    func place(_ cam: Entity, orbit: RoomModelView.Orbit) {
        let pose = Self.cameraPose(shape: shape, orbit: orbit)
        cam.look(at: pose.target, from: pose.from, relativeTo: nil)
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
        // A catalogue piece with a model: draw the model, at the piece's real size, instead of the box.
        if let file = entry.model, !entry.isGhost, let model = ModelCache.shared.cached(file) {
            ModelCache.fit(model, w: Float(entry.widthCm / 100), h: h, d: Float(entry.depthCm / 100))
            model.position.y -= h / 2
            block.model = nil
            block.addChild(model)
        }
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
        if entry.id == selectedId || entry.id == highlightId {
            // A flat accent frame on the floor around the selected thing; wider for the one just placed.
            let pad: Float = entry.id == highlightId ? 0.2 : 0.08
            let ring = ModelEntity(mesh: .generateBox(size: [Float(entry.widthCm / 100) + pad, 0.004, Float(entry.depthCm / 100) + pad]),
                                   materials: [UnlitMaterial(color: UIColor(Color.accent))])
            ring.position = [0, -h / 2 + 0.003, 0]
            block.addChild(ring)
        }
        if entry.problem != nil {
            // Red frame: overlapping something or crossing a wall (drawn over the accent one).
            let warn = ModelEntity(mesh: .generateBox(size: [Float(entry.widthCm / 100) + 0.12, 0.006, Float(entry.depthCm / 100) + 0.12]),
                                   materials: [UnlitMaterial(color: UIColor(Color.danger))])
            warn.position = [0, -h / 2 + 0.004, 0]
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
