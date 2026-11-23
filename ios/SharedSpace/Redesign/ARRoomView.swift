import ARKit
import AVFoundation
import RealityKit
import SwiftUI
import UIKit

// "View in your room": the live camera with furniture at its real size, lined up with the plan.
//
// Privacy: nothing from the camera is uploaded. The only thing kept is ARKit's map of the room
// (Rooms/<id>/worldMap.arworldmap), on this iPhone, so AR can line up again next time.

/// A piece of the plan, as AR needs it (room coordinates, cm and degrees).
struct ARPlanPiece: Identifiable, Equatable {
    let id: UUID              // the placement's id
    let piece: CatalogPiece
    let x: Double
    let z: Double
    let yaw: Double
}

/// A real thing the plan changes. Real objects can't be erased from the camera view, so AR marks
/// them instead: an outline around what's leaving, a marker where a moved thing will go.
struct ARMarker: Identifiable, Equatable {
    enum Kind: Equatable { case leaving, movesHere }
    let id: UUID            // the item's id
    let kind: Kind
    let name: String
    let x: Double, z: Double, yaw: Double
    let w: Double, d: Double, h: Double

    var text: String { kind == .leaving ? "Leaving: \(name)" : "\(name) moves here" }
}

/// What lining up by hand asks for: a corner of the room and the wall leaving it, from the plan.
struct ARAlignGuide {
    let corner: (x: Double, z: Double)
    let along: (x: Double, z: Double)
    let cornerText: String
    let wallText: String

    /// The corner nearest the door and the wall with the door; without a door, one end of the
    /// longest wall.
    static func make(_ shape: RoomShape) -> ARAlignGuide {
        let edges = shape.edges
        if let door = shape.openings.first(where: { $0.kind == .door }), edges.indices.contains(door.edge) {
            let e = edges[door.edge]
            let start = door.position < 0.5
            let c = start ? e.a : e.b, o = start ? e.b : e.a
            return ARAlignGuide(corner: (c.x, c.z), along: (o.x - c.x, o.z - c.z),
                                cornerText: "Tap the floor in the corner of the room nearest the door",
                                wallText: "Now tap the floor partway along the wall with the door")
        }
        let e = edges.max { $0.length < $1.length } ?? edges[0]
        return ARAlignGuide(corner: (e.a.x, e.a.z), along: (e.dx, e.dz),
                            cornerText: "Tap the floor in a corner at one end of the room’s longest wall",
                            wallText: "Now tap the floor partway along that long wall")
    }
}

/// Full-screen AR. Pieces of the plan appear where they were planned once AR lines up with the
/// room; moving them here moves them in the plan, and the other way round.
struct ARRoomView: View {
    let room: Room
    /// Pieces offered in the strip at the bottom.
    let choices: [CatalogPiece]
    var initialPiece: CatalogPiece?
    /// The plan version's pieces (empty for a quick look from the catalogue).
    var plan: [ARPlanPiece] = []
    /// Things leaving the room, and where moved things go.
    var markers: [ARMarker] = []
    /// False for the guest and for saved (locked) versions: plan pieces can't be moved.
    var canEdit = false
    var onMove: (UUID, Double, Double, Double) -> Void = { _, _, _, _ in }
    var onRemove: (UUID) -> Void = { _ in }
    /// Adds a piece to the plan at (x, z, yaw); returns its placement id.
    var onAdd: (CatalogPiece, Double, Double, Double) -> UUID? = { _, _, _, _ in nil }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ar = ARPlacementModel()
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)

    private var units: UnitSystem { room.unitSystem }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !ARWorldTrackingConfiguration.isSupported {
                notice(symbol: "arkit", title: "AR needs an iPhone",
                       text: "This device can’t show furniture in the room. Open Shared Space on an iPhone to try it.")
            } else if camera == .denied || camera == .restricted {
                notice(symbol: "camera", title: "Camera access is off",
                       text: "To see furniture in your room, allow Shared Space to use the camera. The camera view stays on your iPhone.",
                       settings: true)
            } else if camera == .authorized {
                ARViewContainer(model: ar)
                    .ignoresSafeArea()
                    .accessibilityElement()
                    .accessibilityLabel("Camera view of your room")
                    .accessibilityHint(ar.floorFound ? "Use Place here to put the chosen piece in front of you." : "")
                overlays
            }
        }
        .statusBarHidden()
        .task {
            if camera == .notDetermined {
                camera = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
            }
        }
        .onAppear {
            ar.reduceMotion = reduceMotion
            ar.roomId = room.id
            ar.guide = ARAlignGuide.make(room.shape)
            ar.canEdit = canEdit
            ar.plan = plan
            ar.markers = markers
            ar.onMove = onMove
            ar.onRemove = onRemove
            ar.onAdd = onAdd
            if ar.choice == nil { ar.choice = initialPiece ?? choices.first }
        }
        .onChange(of: plan) { _, new in
            // The plan's actions look pieces up by id, so they're refreshed with the plan.
            ar.onMove = onMove
            ar.onRemove = onRemove
            ar.onAdd = onAdd
            ar.syncPlan(new)
        }
        .onChange(of: markers) { _, new in ar.syncMarkers(new) }
        .onChange(of: canEdit) { _, new in ar.canEdit = new }
        .onChange(of: reduceMotion) { _, new in ar.reduceMotion = new }
        .onDisappear { ar.stop() }
    }

    // MARK: Overlays

    private var overlays: some View {
        VStack(spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.s) {
                roundButton("xmark", "Close AR view") { dismiss() }
                Spacer(minLength: 0)
                if ar.loading > 0 {
                    HStack(spacing: Space.s) {
                        ProgressView()
                        Text("Loading…").font(.detailStrong)
                    }
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: Size.tapTarget)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityElement(children: .combine)
                }
                alignButton
            }
            if let status = statusText {
                Text(status)
                    .font(.detailStrong)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.tile))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if !ar.hasLiDAR {
                Text("This iPhone has no LiDAR, so sizes and positions are less precise and real furniture won’t hide pieces.")
                    .font(.detail)
                    .multilineTextAlignment(.center)
                    .padding(Space.s)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.tile))
            }
            Spacer()
            if ar.isLiningUpByHand {
                Button("Cancel lining up") { ar.cancelManual() }
                    .buttonStyle(.app(.neutral))
            } else if let placed = ar.selected {
                pieceBar(placed)
            } else {
                chooser
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.s)
    }

    /// "Line up with your plan", "Line up by hand instead" or "Line up again".
    @ViewBuilder private var alignButton: some View {
        switch ar.alignment {
        case .none where !plan.isEmpty || canEdit:
            pill("Line up with your plan", "scope") { ar.startManual() }
        case .relocalizing where ar.relocalizeIsSlow:
            pill("Line up by hand instead", "hand.tap") { ar.startManual() }
        case .aligned:
            pill("Line up again", "scope") { ar.startManual() }
                .accessibilityHint("If the plan’s pieces aren’t where they should be")
        default:
            EmptyView()
        }
    }

    private var statusText: String? {
        switch ar.alignment {
        case .relocalizing:
            return ar.relocalizeIsSlow
                ? "Still lining up. Point your iPhone at the walls and furniture you scanned, or line up by hand."
                : "Point your iPhone around the room to line things up"
        case .manualCorner:
            return ar.floorFound ? ar.guide?.cornerText : "Move your iPhone slowly to find the floor"
        case .manualWall:
            return ar.guide?.wallText
        case .none, .aligned:
            break
        }
        if !ar.floorFound { return "Move your iPhone slowly to find the floor" }
        if let note = ar.notice { return note }
        if ar.selected != nil { return nil }
        if let choice = ar.choice { return "Tap the floor to place the \(choice.name.lowercased())" }
        return "Choose a piece below"
    }

    /// The pieces to place, and "Place here" (puts it on the floor in the middle of the screen).
    private var chooser: some View {
        VStack(spacing: Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(choices) { piece in
                        let on = ar.choice?.id == piece.id
                        Button { ar.choice = piece } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(piece.name).font(.detailStrong).lineLimit(1)
                                Text(units.dims(piece.w, piece.d, piece.h)).font(.detail).lineLimit(1)
                            }
                            .foregroundStyle(on ? Color.onAccent : Color.textPrimary)
                            .padding(.horizontal, Space.m)
                            .frame(minHeight: Size.tapTarget)
                            .background(on ? AnyShapeStyle(Color.accent) : AnyShapeStyle(.regularMaterial),
                                        in: RoundedRectangle(cornerRadius: Radius.tile))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(piece.name), \(units.dims(piece.w, piece.d, piece.h))")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .scrollClipDisabled()
            if let choice = ar.choice {
                Button { ar.placeAtCenter() } label: {
                    Label("Place here", systemImage: "plus.viewfinder")
                }
                .buttonStyle(.app)
                .disabled(!ar.floorFound || ar.alignment == .relocalizing)
                .accessibilityLabel("Place the \(choice.name.lowercased()) in the middle of the screen")
            }
        }
    }

    /// The selected piece: its name and size, turning, moving with arrows, removing.
    private func pieceBar(_ placed: ARPlacementModel.Placed) -> some View {
        let movable = ar.canMove(placed)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(placed.piece.name).font(.bodyStrong)
                    Text(units.dims(placed.piece.w, placed.piece.d, placed.piece.h)).font(.detail).foregroundStyle(Color.textSecondary)
                    Text(ar.saveNote(placed)).font(.detail).foregroundStyle(Color.textSecondary)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Button("Done") { ar.select(nil) }
                    .buttonStyle(.app(.primary, size: .compact, width: .hug))
            }
            if movable {
                HStack(spacing: Space.xs) {
                    roundButton("arrow.left", "Move left") { ar.nudge(right: -1, forward: 0) }
                    roundButton("arrow.up", "Move away from you") { ar.nudge(right: 0, forward: 1) }
                    roundButton("arrow.down", "Move toward you") { ar.nudge(right: 0, forward: -1) }
                    roundButton("arrow.right", "Move right") { ar.nudge(right: 1, forward: 0) }
                    Spacer(minLength: Space.xs)
                    roundButton("rotate.right", "Rotate 15 degrees") { ar.rotateSelected(by: 15) }
                    roundButton("trash", "Remove \(placed.piece.name)") { ar.removeSelected() }
                }
            }
        }
        .padding(Space.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    private func roundButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.bodyStrong)
                .frame(width: Size.tapTarget, height: Size.tapTarget)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func pill(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.detailStrong)
                .padding(.horizontal, Space.m)
                .frame(minHeight: Size.tapTarget)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func notice(symbol: String, title: String, text: String, settings: Bool = false) -> some View {
        VStack(spacing: Space.l) {
            Image(systemName: symbol).font(.largeTitle).accessibilityHidden(true)
            Text(title).font(.sectionTitle)
            Text(text).multilineTextAlignment(.center)
            if settings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.app)
            }
            Button("Close") { dismiss() }.buttonStyle(.app(.neutral))
        }
        .foregroundStyle(.white)
        .padding(Space.xl)
    }
}

// MARK: - The AR view

private struct ARViewContainer: UIViewRepresentable {
    let model: ARPlacementModel
    func makeUIView(context: Context) -> ARView { model.makeView() }
    func updateUIView(_ view: ARView, context: Context) {}
}

/// Runs the AR session, lines it up with the room, and owns the pieces on screen.
@MainActor
@Observable
final class ARPlacementModel: NSObject, ARSessionDelegate, UIGestureRecognizerDelegate {
    struct Placed: Identifiable {
        let id: UUID
        let piece: CatalogPiece
        let root: Entity
        let ring: Entity
        /// World turn, degrees about +y.
        var yawDeg: Float = 0
        /// Set when it's part of the plan (its placement id).
        var placementId: UUID?
    }

    enum Alignment: Equatable {
        /// Not lined up: pieces are a preview only.
        case none
        /// Matching the saved map from the scan (or an earlier line-up).
        case relocalizing
        /// Lining up by hand: waiting for the corner tap, then the wall tap.
        case manualCorner, manualWall
        case aligned(byHand: Bool)
    }

    var choice: CatalogPiece?
    private(set) var pieces: [UUID: Placed] = [:]
    private(set) var selectedId: UUID?
    private(set) var floorFound = false
    private(set) var loading = 0
    private(set) var alignment: Alignment = .none
    private(set) var relocalizeIsSlow = false
    /// A short message that replaces the usual hint for a moment ("Lined up with your plan").
    private(set) var notice: String?
    let hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    var reduceMotion = false

    // Set by the view.
    var roomId: UUID?
    var guide: ARAlignGuide?
    var canEdit = false
    @ObservationIgnored var plan: [ARPlanPiece] = []
    @ObservationIgnored var markers: [ARMarker] = []
    /// Outlines and "moves here" markers on screen.
    @ObservationIgnored private var markerEntities: [Entity] = []
    @ObservationIgnored var onMove: (UUID, Double, Double, Double) -> Void = { _, _, _, _ in }
    @ObservationIgnored var onRemove: (UUID) -> Void = { _ in }
    @ObservationIgnored var onAdd: (CatalogPiece, Double, Double, Double) -> UUID? = { _, _, _, _ in nil }

    var selected: Placed? { selectedId.flatMap { pieces[$0] } }
    var isLiningUpByHand: Bool { alignment == .manualCorner || alignment == .manualWall }
    private var isAligned: Bool { if case .aligned = alignment { true } else { false } }

    @ObservationIgnored private var arView: ARView?
    @ObservationIgnored private let world = AnchorEntity(world: .zero)
    @ObservationIgnored private var frame: RoomFrame?
    /// The frame saved with the world map, used once relocalizing succeeds.
    @ObservationIgnored private var savedFrame: RoomFrame?
    @ObservationIgnored private var cornerWorld: SIMD3<Float>?
    @ObservationIgnored private var cornerMarker: Entity?
    /// Height of the floor (metres, world space). Pieces always stand on it.
    @ObservationIgnored private var floorY: Float?
    @ObservationIgnored private var floorIsClassified = false
    @ObservationIgnored private var dragId: UUID?
    @ObservationIgnored private var dragOffset: SIMD3<Float> = .zero
    @ObservationIgnored private var twistId: UUID?
    @ObservationIgnored private var twistStart: Float = 0
    /// Plan pieces whose entity is still loading, so they aren't added twice.
    @ObservationIgnored private var loadingPlacements: Set<UUID> = []

    func makeView() -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView = view
        view.session.delegate = self
        view.scene.addAnchor(world)

        // A saved map (from the scan, or an earlier line-up) means AR can find the room by itself.
        if let roomId, let map = RoomFrame.worldMap(roomId), let saved = RoomFrame.load(roomId) {
            savedFrame = saved
            alignment = .relocalizing
            run(map: map)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                if self?.alignment == .relocalizing { self?.relocalizeIsSlow = true }
            }
        } else {
            run(map: nil)
        }

        // Apple's coaching overlay until the floor (or the room) is found.
        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coaching)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        let twist = UIRotationGestureRecognizer(target: self, action: #selector(twisted(_:)))
        // A twist often starts with one finger a moment before the other: let it take over from a drag.
        pan.delegate = self
        twist.delegate = self
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(twist)
        return view
    }

    private func run(map: ARWorldMap?, reset: Bool = false) {
        guard let arView else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        config.initialWorldMap = map
        if hasLiDAR {
            // The room's mesh lets real furniture hide pieces behind it.
            config.sceneReconstruction = .mesh
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)   // people walk in front of pieces
        }
        arView.session.run(config, options: reset ? [.resetTracking, .removeExistingAnchors] : [])
    }

    /// Closing: a line-up made by hand is kept (as a map of the room, on this phone) so next time
    /// AR finds the room by itself.
    func stop() {
        guard let arView else { return }
        let session = arView.session
        if case .aligned(byHand: true) = alignment, let frame, let roomId {
            session.getCurrentWorldMap { map, _ in
                if let map { RoomFrame.saveWorldMap(map, frame: frame, roomId: roomId) }
                session.pause()
            }
        } else {
            session.pause()
        }
    }

    // MARK: Session

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        MainActor.assumeIsolated { noteFloor(anchors) }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        MainActor.assumeIsolated { noteFloor(anchors) }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let normal = if case .normal = camera.trackingState { true } else { false }
        MainActor.assumeIsolated {
            // With a saved map, tracking stays "relocalizing" until ARKit recognises the room.
            if normal, alignment == .relocalizing, let savedFrame { aligned(with: savedFrame, byHand: false) }
        }
    }

    /// The floor is the plane ARKit classifies as floor, or until then the lowest flat surface.
    private func noteFloor(_ anchors: [ARAnchor]) {
        for case let plane as ARPlaneAnchor in anchors where plane.alignment == .horizontal {
            let y = plane.transform.columns.3.y
            let isFloor = ARPlaneAnchor.isClassificationSupported && plane.classification == .floor
            if isFloor {
                if !floorIsClassified || abs((floorY ?? y) - y) > 0.005 { setFloor(y, classified: true) }
            } else if !floorIsClassified, floorY.map({ y < $0 - 0.005 }) ?? true {
                setFloor(y, classified: false)
            }
        }
    }

    private func setFloor(_ y: Float, classified: Bool) {
        floorY = y
        floorIsClassified = classified
        if !floorFound { floorFound = true }
        for placed in pieces.values { placed.root.position.y = y }
        for marker in markerEntities { marker.position.y = y }
        cornerMarker?.position.y = y
    }

    /// Where a screen point's ray meets the floor.
    private func floorPoint(at point: CGPoint) -> SIMD3<Float>? {
        guard let arView, let floorY, let ray = arView.ray(through: point), ray.direction.y < -0.001 else { return nil }
        let t = (floorY - ray.origin.y) / ray.direction.y
        guard t > 0, t < 15 else { return nil }
        return ray.origin + ray.direction * t
    }

    // MARK: Lining up

    func startManual() {
        select(nil)
        // Relocalizing never finished: start a fresh session, so taps aren't measured in a world
        // ARKit is still trying to match.
        if alignment == .relocalizing { run(map: nil, reset: true); floorY = nil; floorFound = false; floorIsClassified = false }
        cornerWorld = nil
        cornerMarker?.removeFromParent()
        cornerMarker = nil
        alignment = .manualCorner
        if let text = guide?.cornerText { UIAccessibility.post(notification: .announcement, argument: text) }
    }

    func cancelManual() {
        cornerMarker?.removeFromParent()
        cornerMarker = nil
        cornerWorld = nil
        alignment = frame == nil ? .none : .aligned(byHand: true)
    }

    private func manualTap(at point: CGPoint) {
        guard let spot = floorPoint(at: point), let guide else { return }
        if alignment == .manualCorner {
            cornerWorld = spot
            let dot = ModelEntity(mesh: .generateSphere(radius: 0.03), materials: [UnlitMaterial(color: UIColor(Color.accent))])
            dot.position = spot
            world.addChild(dot)
            cornerMarker = dot
            alignment = .manualWall
            UIAccessibility.post(notification: .announcement, argument: guide.wallText)
        } else if alignment == .manualWall, let cornerWorld {
            guard let f = RoomFrame.fromTaps(corner: guide.corner, along: guide.along, cornerWorld: cornerWorld, wallWorld: spot) else {
                flash("Tap a little further along the wall")
                return
            }
            cornerMarker?.removeFromParent()
            cornerMarker = nil
            aligned(with: f, byHand: true)
        }
    }

    /// Lined up: put the plan's pieces where they were planned. Preview pieces stay where they are.
    private func aligned(with f: RoomFrame, byHand: Bool) {
        frame = f
        alignment = .aligned(byHand: byHand)
        relocalizeIsSlow = false
        if floorY == nil { floorY = f.originY; floorFound = true }
        for placed in pieces.values where placed.placementId != nil {
            placed.root.removeFromParent()
            pieces[placed.id] = nil
        }
        syncPlan(plan)
        syncMarkers(markers)
        // The outlines are only visible, so say what they show.
        let leaving = markers.filter { $0.kind == .leaving }.map(\.name)
        let moving = markers.filter { $0.kind == .movesHere }.map(\.name)
        var text = plan.isEmpty && moving.isEmpty ? "Lined up with your room" : "Lined up with your plan"
        if !leaving.isEmpty { text += ". Leaving: \(leaving.formatted(.list(type: .and)))" }
        if !moving.isEmpty { text += ". Moving: \(moving.formatted(.list(type: .and)))" }
        flash(text)
    }

    /// The plan changed (here, in the plan tab, or on the other phone): match it.
    func syncPlan(_ new: [ARPlanPiece]) {
        plan = new
        guard let frame, isAligned else { return }
        let byPlacement = Dictionary(uniqueKeysWithValues: pieces.values.compactMap { p in p.placementId.map { ($0, p) } })
        for entry in new {
            if let placed = byPlacement[entry.id] {
                guard dragId != placed.id, twistId != placed.id else { continue }
                var p = placed
                let target = frame.toWorld(x: entry.x, z: entry.z, floorY: floorY)
                if simd_distance(target, placed.root.position) > 0.01 { placed.root.position = target }
                let yaw = frame.worldYawDeg(roomYaw: entry.yaw)
                if abs(yaw - placed.yawDeg) > 0.5 {
                    p.yawDeg = yaw
                    placed.root.orientation = simd_quatf(angle: yaw * .pi / 180, axis: [0, 1, 0])
                    pieces[p.id] = p
                }
            } else if !loadingPlacements.contains(entry.id) {
                add(entry.piece, at: frame.toWorld(x: entry.x, z: entry.z, floorY: floorY),
                    yawDeg: frame.worldYawDeg(roomYaw: entry.yaw), placementId: entry.id, select: false)
            }
        }
        let live = Set(new.map(\.id))
        for placed in pieces.values where placed.placementId.map({ !live.contains($0) }) ?? false {
            placed.root.removeFromParent()
            pieces[placed.id] = nil
            if selectedId == placed.id { selectedId = nil }
        }
    }

    /// Rebuilds the outlines and markers (there are only a few, so they're simply redrawn).
    func syncMarkers(_ new: [ARMarker]) {
        markers = new
        markerEntities.forEach { $0.removeFromParent() }
        markerEntities = []
        guard let frame, isAligned else { return }
        for m in new {
            let e = m.kind == .leaving ? MarkerEntity.leaving(m) : MarkerEntity.movesHere(m)
            e.position = frame.toWorld(x: m.x, z: m.z, floorY: floorY)
            e.orientation = simd_quatf(angle: frame.worldYawDeg(roomYaw: m.yaw) * .pi / 180, axis: [0, 1, 0])
            world.addChild(e)
            markerEntities.append(e)
        }
    }

    private func flash(_ text: String) {
        notice = text
        UIAccessibility.post(notification: .announcement, argument: text)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if self?.notice == text { self?.notice = nil }
        }
    }

    // MARK: Placing

    func canMove(_ placed: Placed) -> Bool { placed.placementId == nil || canEdit }

    /// What the bar says about saving.
    func saveNote(_ placed: Placed) -> String {
        if placed.placementId != nil { return canEdit ? "In the plan. Changes save to it." : "In the plan" }
        if isAligned { return "Preview only" }
        return "Preview. Line up with your plan to save pieces."
    }

    func placeAtCenter() {
        guard let arView else { return }
        place(at: CGPoint(x: arView.bounds.midX, y: arView.bounds.midY))
    }

    private func place(at point: CGPoint) {
        guard let choice, let spot = floorPoint(at: point), alignment != .relocalizing else { return }
        let yaw = facingYaw()
        var placementId: UUID?
        // Lined up and allowed to edit: it goes into the plan.
        if let frame, isAligned, canEdit {
            let p = frame.toRoom(spot)
            placementId = onAdd(choice, p.x, p.z, PlacementCheck.snapYaw(frame.roomYawDeg(worldYaw: yaw)))
        }
        add(choice, at: spot, yawDeg: yaw, placementId: placementId, select: true)
    }

    private func add(_ piece: CatalogPiece, at spot: SIMD3<Float>, yawDeg: Float, placementId: UUID?, select shouldSelect: Bool) {
        let id = UUID()
        loading += 1
        if let placementId { loadingPlacements.insert(placementId) }
        Task {
            let (root, ring) = await PieceEntity.make(piece)
            loading -= 1
            if let placementId { loadingPlacements.remove(placementId) }
            // The plan may have dropped it while it loaded.
            if let placementId, !plan.contains(where: { $0.id == placementId }), !shouldSelect { return }
            root.name = id.uuidString
            root.position = spot
            root.orientation = simd_quatf(angle: yawDeg * .pi / 180, axis: [0, 1, 0])
            world.addChild(root)
            pieces[id] = Placed(id: id, piece: piece, root: root, ring: ring, yawDeg: yawDeg, placementId: placementId)
            if !reduceMotion {
                let final = root.transform
                root.scale = [0.85, 0.85, 0.85]
                root.move(to: final, relativeTo: root.parent, duration: 0.2, timingFunction: .easeOut)
            }
            if shouldSelect {
                select(id)
                UIAccessibility.post(notification: .announcement, argument: "Placed \(piece.name)")
            }
        }
    }

    func select(_ id: UUID?) {
        if let old = selectedId { pieces[old]?.ring.isEnabled = false }
        selectedId = id
        if let id { pieces[id]?.ring.isEnabled = true }
    }

    func removeSelected() {
        guard let id = selectedId, let placed = pieces[id], canMove(placed) else { return }
        placed.root.removeFromParent()
        pieces[id] = nil
        selectedId = nil
        if let pid = placed.placementId { onRemove(pid) }
        UIAccessibility.post(notification: .announcement, argument: "Removed \(placed.piece.name)")
    }

    func rotateSelected(by degrees: Float) {
        guard let id = selectedId, let placed = pieces[id], canMove(placed) else { return }
        setYaw(id, snap(placed.yawDeg - degrees))
        commit(id)
    }

    /// Arrow buttons: 10 cm along the floor, relative to where the iPhone is pointing.
    func nudge(right: Float, forward: Float) {
        guard let id = selectedId, let placed = pieces[id], canMove(placed), let arView else { return }
        let m = arView.cameraTransform.matrix
        var ahead = SIMD3<Float>(-m.columns.2.x, 0, -m.columns.2.z)
        var side = SIMD3<Float>(m.columns.0.x, 0, m.columns.0.z)
        if simd_length(ahead) > 0.001 { ahead = simd_normalize(ahead) }
        if simd_length(side) > 0.001 { side = simd_normalize(side) }
        placed.root.position += (ahead * forward + side * right) * 0.1
        commit(id)
    }

    /// Saves a plan piece's new spot to the plan.
    private func commit(_ id: UUID) {
        guard let placed = pieces[id], let pid = placed.placementId, canEdit, let frame else { return }
        let p = frame.toRoom(placed.root.position)
        onMove(pid, p.x, p.z, PlacementCheck.snapYaw(frame.roomYawDeg(worldYaw: placed.yawDeg)))
    }

    private func setYaw(_ id: UUID, _ deg: Float) {
        guard var placed = pieces[id] else { return }
        placed.yawDeg = deg
        pieces[id] = placed
        placed.root.orientation = simd_quatf(angle: deg * .pi / 180, axis: [0, 1, 0])
    }

    /// Snaps to 15°: square to the room's walls once lined up, else to the world.
    private func snap(_ deg: Float) -> Float {
        guard let frame, isAligned else { return (deg / 15).rounded() * 15 }
        let room = (frame.roomYawDeg(worldYaw: deg) / 15).rounded() * 15
        return frame.worldYawDeg(roomYaw: room)
    }

    /// A new piece faces the camera.
    private func facingYaw() -> Float {
        guard let m = arView?.cameraTransform.matrix else { return 0 }
        let back = SIMD3<Float>(m.columns.2.x, 0, m.columns.2.z)   // from the scene toward the camera
        return snap(atan2(back.x, back.z) * 180 / .pi)
    }

    /// The placed piece under a screen point, if any.
    private func piece(at point: CGPoint) -> UUID? {
        var entity = arView?.entity(at: point)
        while let e = entity {
            if let id = UUID(uuidString: e.name), pieces[id] != nil { return id }
            entity = e.parent
        }
        return nil
    }

    // MARK: Gestures

    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer,
                                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        (g is UIPanGestureRecognizer && other is UIRotationGestureRecognizer)
            || (g is UIRotationGestureRecognizer && other is UIPanGestureRecognizer)
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let point = g.location(in: g.view)
        if isLiningUpByHand { manualTap(at: point); return }
        if let id = piece(at: point) {
            select(id)
        } else if selectedId != nil {
            select(nil)       // tapping the floor while something is selected just puts it down
        } else {
            place(at: point)
        }
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        guard !isLiningUpByHand else { return }
        let point = g.location(in: g.view)
        switch g.state {
        case .began:
            guard let id = piece(at: point), let placed = pieces[id], let hit = floorPoint(at: point) else { dragId = nil; return }
            select(id)
            guard canMove(placed) else { dragId = nil; return }
            dragId = id
            dragOffset = placed.root.position - hit
        case .changed:
            // Two fingers down: it's a twist now, so stop moving.
            guard g.numberOfTouches == 1, twistId == nil else { return }
            guard let id = dragId, let placed = pieces[id], let hit = floorPoint(at: point), let floorY else { return }
            var p = hit + dragOffset
            p.y = floorY
            placed.root.position = p
        default:
            if let id = dragId { commit(id) }
            dragId = nil
        }
    }

    @objc private func twisted(_ g: UIRotationGestureRecognizer) {
        guard !isLiningUpByHand else { return }
        switch g.state {
        case .began:
            twistId = piece(at: g.location(in: g.view)) ?? selectedId
            if let id = twistId, let placed = pieces[id] {
                select(id)
                if canMove(placed) { twistStart = placed.yawDeg } else { twistId = nil }
            }
        case .changed:
            guard let id = twistId else { return }
            setYaw(id, twistStart - Float(g.rotation) * 180 / .pi)
        case .ended, .cancelled:
            if let id = twistId {
                setYaw(id, snap(pieces[id]?.yawDeg ?? 0))
                commit(id)
            }
            twistId = nil
        default:
            break
        }
    }
}

// MARK: - Markers

/// Outlines for what's leaving and markers for where things move. They aren't solid and can't be
/// tapped, so pieces behind them stay easy to reach.
enum MarkerEntity {
    /// A see-through box a little bigger than the thing, with bright edges and "Leaving: Desk".
    /// It's padded so the edges sit just outside the real object, where they aren't hidden by it.
    @MainActor
    static func leaving(_ m: ARMarker) -> Entity {
        let pad: Float = 0.03
        let w = Float(m.w) / 100 + pad * 2, d = Float(m.d) / 100 + pad * 2, h = Float(max(m.h, 5)) / 100 + pad
        let colour = UIColor(Color.danger)
        let root = Entity()
        var fill = UnlitMaterial(color: colour)
        fill.blending = .transparent(opacity: 0.18)
        let box = ModelEntity(mesh: .generateBox(width: w, height: h, depth: d), materials: [fill])
        box.position.y = h / 2
        root.addChild(box)
        for edge in edges(w: w, h: h, d: d) {
            let bar = ModelEntity(mesh: .generateBox(size: edge.size), materials: [UnlitMaterial(color: colour)])
            bar.position = edge.at
            root.addChild(bar)
        }
        let tag = PieceEntity.label(m.text)
        tag.position.y = h + 0.12
        root.addChild(tag)
        return root
    }

    /// The thing's footprint on the floor where it will go, with "Desk moves here".
    @MainActor
    static func movesHere(_ m: ARMarker) -> Entity {
        let w = Float(m.w) / 100, d = Float(m.d) / 100
        let colour = UIColor(Color.accent)
        let root = Entity()
        var fill = UnlitMaterial(color: colour)
        fill.blending = .transparent(opacity: 0.3)
        let pad = ModelEntity(mesh: .generatePlane(width: w, depth: d, cornerRadius: 0.03), materials: [fill])
        pad.position.y = 0.006
        root.addChild(pad)
        // A rim around the footprint, so it reads on any floor.
        let t: Float = 0.02
        for (size, at) in [(SIMD3<Float>(w, 0.004, t), SIMD3<Float>(0, 0.008, -d / 2)), (SIMD3(w, 0.004, t), SIMD3(0, 0.008, d / 2)),
                           (SIMD3(t, 0.004, d), SIMD3(-w / 2, 0.008, 0)), (SIMD3(t, 0.004, d), SIMD3(w / 2, 0.008, 0))] {
            let bar = ModelEntity(mesh: .generateBox(size: size), materials: [UnlitMaterial(color: colour)])
            bar.position = at
            root.addChild(bar)
        }
        let tag = PieceEntity.label(m.text)
        tag.position.y = 0.35
        root.addChild(tag)
        return root
    }

    /// The 12 edges of a box standing on y = 0, as thin bars.
    private static func edges(w: Float, h: Float, d: Float) -> [(size: SIMD3<Float>, at: SIMD3<Float>)] {
        let t: Float = 0.012
        var out: [(SIMD3<Float>, SIMD3<Float>)] = []
        for y in [Float(0), h] {
            out.append(([w, t, t], [0, y, -d / 2])); out.append(([w, t, t], [0, y, d / 2]))
            out.append(([t, t, d], [-w / 2, y, 0])); out.append(([t, t, d], [w / 2, y, 0]))
        }
        for x in [-w / 2, w / 2] { for z in [-d / 2, d / 2] { out.append(([t, h, t], [x, h / 2, z])) } }
        return out
    }
}

// MARK: - Pieces

/// A piece's 3D entity at true size, standing on y = 0: its catalogue model (Resources/Furniture)
/// when it has one, otherwise a box with its name over it.
enum PieceEntity {
    @MainActor
    static func make(_ piece: CatalogPiece) async -> (root: Entity, ring: Entity) {
        let w = Float(piece.w) / 100, d = Float(piece.d) / 100, h = Float(max(piece.h, 1)) / 100
        let root = Entity()
        if let file = piece.model, let model = await ModelCache.shared.load(file) {
            // The catalogue's real model, scaled to the piece's real size.
            ModelCache.fit(model, w: w, h: h, d: d)
            root.addChild(model)
        } else {
            let colour = UIColor(Color.material(piece.colorHex))
            let box = ModelEntity(mesh: .generateBox(width: w, height: h, depth: d, cornerRadius: min(0.02, h / 2)),
                                  materials: [SimpleMaterial(color: colour, roughness: 0.7, isMetallic: false)])
            box.position.y = h / 2
            root.addChild(box)
            let tag = label(piece.name)
            tag.position.y = h + 0.12
            root.addChild(tag)
        }
        // Hit area for taps and drags.
        root.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(width: w, height: h, depth: d)
                                                            .offsetBy(translation: [0, h / 2, 0])]))
        // Selection: an outline on the floor around it.
        let ring = ModelEntity(mesh: .generatePlane(width: w + 0.08, depth: d + 0.08, cornerRadius: 0.04),
                               materials: [UnlitMaterial(color: UIColor(Color.accent).withAlphaComponent(0.55))])
        ring.position.y = 0.004
        ring.isEnabled = false
        root.addChild(ring)
        return (root, ring)
    }

    /// A small label that always faces the camera.
    @MainActor
    static func label(_ text: String) -> Entity {
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.05, weight: .semibold),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
        let b = mesh.bounds
        let words = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: UIColor(Color.onPhotoText))])
        words.position = [-b.center.x, -b.center.y, 0.002]
        let plate = ModelEntity(mesh: .generatePlane(width: b.extents.x + 0.05, height: b.extents.y + 0.03, cornerRadius: 0.015),
                                materials: [UnlitMaterial(color: UIColor(Color.photoBadge))])
        let holder = Entity()
        holder.addChild(plate)
        holder.addChild(words)
        holder.components.set(BillboardComponent())
        return holder
    }
}
