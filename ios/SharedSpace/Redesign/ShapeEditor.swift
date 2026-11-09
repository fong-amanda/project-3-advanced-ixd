import SwiftUI

/// Edit a room's outline: pick a preset, drag corners (tap a wall's + to add one), and place
/// doors and windows. Every drag also has buttons, so nothing depends on dragging.
struct ShapeEditor: View {
    @Binding var shape: RoomShape
    let units: UnitSystem

    @State private var selectedCorner: Int?
    @State private var selectedOpening: UUID?
    @State private var drag: DragTarget?

    private enum DragTarget { case corner(Int), opening(UUID), empty }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    let current = shape.matchingPreset()
                    ForEach(RoomShape.Preset.allCases) { preset in
                        AppChip(title: preset.label, isSelected: current == preset) {
                            let b = shape.bounds
                            shape = .preset(preset, width: b.maxX, length: b.maxZ)
                            selectedCorner = nil
                            selectedOpening = nil
                        }
                    }
                    if current == nil { AppChip(title: "Custom", isSelected: true) {}.disabled(true) }
                }
            }
            .scrollClipDisabled()

            canvas
                .aspectRatio(1, contentMode: .fit)
                .card(.outlined, padding: 0, radius: Radius.l)

            FlowLayout(spacing: Space.s) {
                AppChip(title: "+ Door", isSelected: false) { addOpening(.door) }
                AppChip(title: "+ Window", isSelected: false) { addOpening(.window) }
            }
            if let id = selectedOpening, let o = shape.openings.first(where: { $0.id == id }) { openingControls(o) }
            if let i = selectedCorner, i < shape.corners.count { cornerControls(i) }

            HStack {
                Text("\(units.roomLength(shape.bounds.maxX)) × \(units.roomLength(shape.bounds.maxZ)) · \(units.area(shape.area))")
                    .textRole(.bodyStrong)
                Spacer()
            }
            if shape.selfIntersects {
                NoteBar(text: "Two walls cross. Move a corner so the walls don’t cross.", symbol: "exclamationmark.triangle", tone: .warning)
            } else {
                Text("Drag corners, the door and the window. Tap + on a wall to add a corner.").textRole(.hint)
            }
        }
    }

    // MARK: Canvas

    private func transform(_ size: CGSize) -> PlanTransform {
        let b = shape.bounds
        let side = max(b.maxX, b.maxZ, 300) + 160
        let scale = size.width / side
        return PlanTransform(scale: scale, origin: CGPoint(x: (size.width - b.maxX * scale) / 2, y: (size.height - b.maxZ * scale) / 2))
    }

    private var canvas: some View {
        GeometryReader { geo in
            let t = transform(geo.size)
            Canvas { c, size in
                // Grid every metre.
                var grid = Path()
                let step = 100 * t.scale
                var x = t.origin.x.truncatingRemainder(dividingBy: step)
                while x < size.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y = t.origin.y.truncatingRemainder(dividingBy: step)
                while y < size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                c.stroke(grid, with: .color(.outline), lineWidth: Stroke.hairline)

                ShapeDrawing.drawFloor(shape, t, fill: .accentSoft, in: &c)
                c.stroke(ShapeDrawing.outline(shape, t), with: .color(.accent),
                         style: StrokeStyle(lineWidth: Stroke.heavy, lineJoin: .round))

                for e in shape.edges {
                    let mid = e.point(at: 0.5)
                    let n = shape.inwardNormal(e)
                    if e.length >= 50 {
                        let label = Text(units.roomLength(e.length)).font(.captionStrong).foregroundStyle(Color.textSecondary)
                        c.draw(label, at: t.point(mid.x - n.x * 24 / t.scale * 1.2, mid.z - n.z * 24 / t.scale * 1.2))
                    }
                    if e.length >= 60 {
                        let p = t.point(mid.x, mid.z)
                        let r = Size.tick / 4
                        c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.accent))
                        c.draw(Text(Image(systemName: "plus")).font(.captionStrong).foregroundStyle(Color.onAccent), at: p)
                    }
                }
                ShapeDrawing.drawOpenings(shape, t, selected: selectedOpening, handles: true, in: &c)
                for (i, corner) in shape.corners.enumerated() {
                    let p = t.point(corner.x, corner.z)
                    let r = Size.tick / 3
                    let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    c.fill(dot, with: .color(i == selectedCorner ? .accent : .surface))
                    c.stroke(dot, with: .color(.accent), lineWidth: Stroke.heavy)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in changed(value, t) }
                .onEnded { value in ended(value, t) })
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Room shape, \(shape.corners.count) corners, \(shape.openings.count) doors and windows")
        .accessibilityChildren {
            ForEach(Array(shape.corners.indices), id: \.self) { i in
                Rectangle()
                    .accessibilityLabel("Corner \(i + 1)")
                    .accessibilityAddTraits(i == selectedCorner ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { selectedCorner = i; selectedOpening = nil }
            }
            ForEach(shape.openings) { o in
                Rectangle()
                    .accessibilityLabel(o.kind == .door ? "Door" : "Window")
                    .accessibilityAddTraits(o.id == selectedOpening ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { selectedOpening = o.id; selectedCorner = nil }
            }
        }
    }

    private func changed(_ value: DragGesture.Value, _ t: PlanTransform) {
        if drag == nil {
            drag = hit(value.startLocation, t)
            switch drag {
            case .corner(let i): selectedCorner = i; selectedOpening = nil
            case .opening(let id): selectedOpening = id; selectedCorner = nil
            default: break
            }
        }
        let p = t.cm(value.location)
        switch drag {
        case .corner(let i):
            shape.moveCorner(i, x: p.x, z: p.z)
        case .opening(let id):
            guard let k = shape.openings.firstIndex(where: { $0.id == id }) else { return }
            let near = shape.nearestEdge(x: p.x, z: p.z)
            shape.openings[k].edge = near.edge
            shape.openings[k].position = near.position
        default: break
        }
    }

    private func ended(_ value: DragGesture.Value, _ t: PlanTransform) {
        defer { drag = nil }
        if case .empty = drag, hypot(value.translation.width, value.translation.height) < 6 {
            selectedCorner = nil
            selectedOpening = nil
        }
    }

    /// Corners first, then doors and windows, then a wall's + (which adds a corner and drags it).
    private func hit(_ point: CGPoint, _ t: PlanTransform) -> DragTarget {
        let reach = Size.tapTarget / 2
        func dist(_ x: Double, _ z: Double) -> Double { hypot(t.point(x, z).x - point.x, t.point(x, z).y - point.y) }
        if let i = shape.corners.indices.min(by: { dist(shape.corners[$0].x, shape.corners[$0].z) < dist(shape.corners[$1].x, shape.corners[$1].z) }),
           dist(shape.corners[i].x, shape.corners[i].z) < reach {
            return .corner(i)
        }
        for o in shape.openings {
            if let p = shape.placement(of: o), dist(p.center.x, p.center.z) < reach { return .opening(o.id) }
        }
        for e in shape.edges where e.length >= 60 {
            let mid = e.point(at: 0.5)
            if dist(mid.x, mid.z) < reach * 0.8 { return .corner(shape.insertCorner(onEdge: e.index)) }
        }
        return .empty
    }

    // MARK: Controls

    private func addOpening(_ kind: RoomShape.Opening.Kind) {
        let spot = shape.bestEdgeForNewOpening()
        let o = RoomShape.Opening(kind: kind, edge: spot.edge, position: spot.position,
                                  width: kind == .door ? RoomShape.defaultDoorWidth : RoomShape.defaultWindowWidth)
        shape.openings.append(o)
        selectedOpening = o.id
        selectedCorner = nil
    }

    private func openingControls(_ o: RoomShape.Opening) -> some View {
        let k = shape.openings.firstIndex { $0.id == o.id }!
        let range = o.kind == .door ? RoomShape.doorWidthRange : RoomShape.windowWidthRange
        return VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(o.kind == .door ? "Door" : "Window")
            if o.kind == .door {
                FlowLayout(spacing: Space.s) {
                    AppChip(title: o.swingsIn ? "Swings in" : "Swings out", isSelected: false) { shape.openings[k].swingsIn.toggle() }
                    AppChip(title: o.hingeAtEnd ? "Hinge on the right" : "Hinge on the left", isSelected: false) { shape.openings[k].hingeAtEnd.toggle() }
                }
            }
            LengthStepper(label: "Width", value: Binding(get: { shape.openings[k].width },
                                                         set: { shape.openings[k].width = $0 }),
                          range: range, units: units)
            Button("Remove \(o.kind == .door ? "door" : "window")", role: .destructive) {
                shape.openings.remove(at: k)
                selectedOpening = nil
            }
            .buttonStyle(.link(.destructive))
        }
    }

    private func cornerControls(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel("Corner \(i + 1)")
            HStack(spacing: Space.s) {
                Text("Move").textRole(.secondary)
                nudge(i, dx: -1, dz: 0, "arrow.left", "Move corner left")
                nudge(i, dx: 0, dz: -1, "arrow.up", "Move corner toward the back")
                nudge(i, dx: 0, dz: 1, "arrow.down", "Move corner toward the front")
                nudge(i, dx: 1, dz: 0, "arrow.right", "Move corner right")
            }
            if shape.corners.count > 3 {
                Button("Remove corner", role: .destructive) {
                    shape.removeCorner(i)
                    selectedCorner = nil
                }
                .buttonStyle(.link(.destructive))
            }
        }
    }

    private func nudge(_ i: Int, dx: Double, dz: Double, _ symbol: String, _ label: String) -> some View {
        IconButton(symbol: symbol, label: label, filled: true) {
            let c = shape.corners[i]
            shape.moveCorner(i, x: c.x + dx * RoomShape.snap, z: c.z + dz * RoomShape.snap)
        }
    }
}

/// "Walls, door & windows" from the room plan: edit the outline and ceiling height, then save.
struct ShapeEditorSheet: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @State private var shape = RoomShape.rectangle(width: 340, length: 380)
    @State private var height = 250.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    ShapeEditor(shape: $shape, units: room.unitSystem)
                    LengthStepper(label: "Width", value: Binding(get: { shape.bounds.maxX },
                                                                 set: { shape = shape.scaled(toWidth: $0, length: shape.bounds.maxZ) }),
                                  range: 150...2000, units: room.unitSystem)
                    LengthStepper(label: "Length", value: Binding(get: { shape.bounds.maxZ },
                                                                  set: { shape = shape.scaled(toWidth: shape.bounds.maxX, length: $0) }),
                                  range: 150...2000, units: room.unitSystem)
                    LengthStepper(label: "Ceiling", value: $height, range: 200...400, units: room.unitSystem)
                }
                .pagePadding()
            }
            .background(Color.pageBackground)
            .navigationTitle("Walls, door & windows")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        room.shape = shape
                        room.heightCm = Int(height.rounded())
                        sync.save(room)
                        dismiss()
                    }
                    .disabled(shape.selfIntersects)
                }
            }
            .onAppear {
                shape = room.shape
                height = Double(room.heightCm)
            }
        }
    }
}
