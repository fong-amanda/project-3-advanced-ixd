import SwiftUI

/// Top-down floor plan of a room and its things. Back wall at the top, like the prototype.
///
/// Interactive when the callbacks are set: tap a thing (or a freed-up zone) to select it, drag a
/// placed piece to move it. Dragging is never the only way: the piece bar has move buttons too.
struct FloorPlanView: View {
    let room: Room
    let entries: [PlanEntry]
    var showLabels = true
    /// Draw removed things as dashed outlines (otherwise they're left out).
    var showGhosts = false
    var selectedId: UUID?
    var onSelect: ((UUID?) -> Void)?
    var zones: [FreeZone] = []
    var selectedZone: Int?
    var onSelectZone: ((Int?) -> Void)?
    /// Called when a placed piece is dropped somewhere new (centre, in cm).
    var onMovePiece: ((UUID, Double, Double) -> Void)?

    @State private var drag: (id: UUID, dx: Double, dz: Double, x: Double, z: Double, moved: Bool)?

    var body: some View {
        GeometryReader { geo in
            let map = PlanMap(size: geo.size, room: room)
            Canvas { context, _ in draw(in: &context, map: map) }
                .contentShape(Rectangle())
                .gesture(gesture(map), including: onSelect == nil && onMovePiece == nil ? .subviews : .all)
        }
        .aspectRatio(CGFloat(room.widthCm) / CGFloat(max(room.lengthCm, 1)), contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityChildren {
            ForEach(entries.filter { !$0.isGhost && onSelect != nil }) { entry in
                Rectangle()
                    .accessibilityLabel(entry.style == .newPiece ? "\(entry.name), placed in the plan" : entry.name)
                    .accessibilityValue(entry.problem ?? "")
                    .accessibilityAddTraits(entry.id == selectedId ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { onSelect?(entry.id == selectedId ? nil : entry.id) }
            }
        }
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, map: PlanMap) {
        let shape = room.shape
        let t = PlanTransform(scale: map.scale, origin: map.origin)
        ShapeDrawing.drawFloor(shape, t, fill: .surface, in: &context)

        for zone in zones {
            let r = map.rect(zone.rect)
            let on = zone.id == selectedZone
            context.fill(Path(roundedRect: r, cornerRadius: Radius.drawing), with: .color(Color.tintSage.opacity(on ? Opacity.zoneFillSelected : Opacity.zoneFill)))
            context.stroke(Path(roundedRect: r, cornerRadius: Radius.drawing), with: .color(.accent),
                           style: StrokeStyle(lineWidth: on ? Stroke.bold : Stroke.regular, dash: Stroke.dashed))
        }

        // Flat things (rugs) first, then ghosts, then everything standing on the floor, pieces last.
        let ordered = entries.filter { $0.isFlat && !$0.isGhost }
            + entries.filter { $0.isGhost && showGhosts }
            + entries.filter { !$0.isFlat && !$0.isGhost && $0.style != .newPiece }
            + entries.filter { !$0.isFlat && $0.style == .newPiece }

        for entry in ordered {
            var c = context
            let (x, z) = position(of: entry)
            c.translateBy(x: map.origin.x + x * map.scale, y: map.origin.y + z * map.scale)
            c.rotate(by: .degrees(entry.yawDeg))
            let rect = CGRect(x: -entry.widthCm * map.scale / 2, y: -entry.depthCm * map.scale / 2,
                              width: entry.widthCm * map.scale, height: entry.depthCm * map.scale)
            let shape = Path(roundedRect: rect, cornerRadius: Radius.drawing)
            style(entry, shape: shape, in: &c)

            if showLabels && !entry.isFlat && rect.width > 40 && rect.height > 20 {
                c.rotate(by: .degrees(-entry.yawDeg))
                let text = Text(entry.name)
                    .font(.planLabel(fitting: rect.width))
                    .foregroundStyle(entry.isGhost ? Color.textSecondary : Color.textPrimary)
                c.draw(text, in: CGRect(x: -rect.width / 2 + 2, y: -rect.height / 2, width: rect.width - 4, height: rect.height))
            }
        }

        ShapeDrawing.drawWalls(shape, t, in: &context)
        ShapeDrawing.drawOpenings(shape, t, in: &context)
    }

    private func position(of entry: PlanEntry) -> (Double, Double) {
        if let d = drag, d.id == entry.id, d.moved { return (d.x, d.z) }
        return (entry.xCm, entry.zCm)
    }

    private func style(_ entry: PlanEntry, shape: Path, in c: inout GraphicsContext) {
        let selected = entry.id == selectedId
        switch entry.style {
        case .normal:
            c.fill(shape, with: .color(entry.isFlat ? Color.material(entry.colorHex).opacity(Opacity.rugFill) : .tintBrown))
            c.stroke(shape, with: .color(entry.isFlat ? .clear : .iconNeutral), lineWidth: Stroke.regular)
        case .moved:
            c.fill(shape, with: .color(.tintBrown))
            c.stroke(shape, with: .color(.iconNeutral), lineWidth: Stroke.bold)
        case .newPiece:
            c.fill(shape, with: .color(entry.isFlat ? Color.tintSage.opacity(Opacity.zoneFill) : .tintSage))
            if entry.problem != nil {
                c.stroke(shape, with: .color(.letGo), style: StrokeStyle(lineWidth: Stroke.bold, dash: Stroke.dashed))
            } else {
                c.stroke(shape, with: .color(.accent), style: StrokeStyle(lineWidth: Stroke.bold, dash: Stroke.dashed))
            }
        case .leaving(let status):
            c.stroke(shape, with: .color(status.color), style: StrokeStyle(lineWidth: Stroke.regular, dash: Stroke.dashed))
        case .hiddenInDesign:
            c.stroke(shape, with: .color(.textSecondary), style: StrokeStyle(lineWidth: Stroke.regular, dash: Stroke.dotted))
        }
        if selected { c.stroke(shape, with: .color(.accent), lineWidth: Stroke.heavy) }
    }

    // MARK: Touch

    private func gesture(_ map: PlanMap) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = map.cm(value.location)
                if drag == nil {
                    let start = map.cm(value.startLocation)
                    guard let hit = hit(start), hit.style == .newPiece, onMovePiece != nil else {
                        drag = (UUID(), 0, 0, 0, 0, false)   // a tap or a pan that isn't on a piece
                        return
                    }
                    drag = (hit.id, hit.xCm - start.x, hit.zCm - start.z, hit.xCm, hit.zCm, false)
                }
                guard var d = drag, entries.contains(where: { $0.id == d.id }) else { return }
                if hypot(value.translation.width, value.translation.height) > 5 { d.moved = true }
                d.x = ((p.x + d.dx) / 5).rounded() * 5
                d.z = ((p.z + d.dz) / 5).rounded() * 5
                drag = d
            }
            .onEnded { value in
                defer { drag = nil }
                if let d = drag, d.moved, entries.contains(where: { $0.id == d.id }) {
                    onSelect?(d.id)
                    onMovePiece?(d.id, d.x, d.z)
                    return
                }
                guard hypot(value.translation.width, value.translation.height) < 8 else { return }
                let p = map.cm(value.location)
                if let hit = hit(p) {
                    onSelect?(hit.id == selectedId ? nil : hit.id)
                } else if let zone = zones.first(where: { p.x >= $0.rect.x && p.x <= $0.rect.maxX && p.z >= $0.rect.z && p.z <= $0.rect.maxZ }) {
                    onSelectZone?(zone.id == selectedZone ? nil : zone.id)
                } else {
                    onSelect?(nil)
                }
            }
    }

    /// Topmost thing under a point: pieces first, then things standing on the floor, then rugs.
    private func hit(_ p: (x: Double, z: Double)) -> PlanEntry? {
        let candidates = entries.filter { !$0.isGhost }
        let order = candidates.filter { $0.style == .newPiece && !$0.isFlat }
            + candidates.filter { $0.style != .newPiece && !$0.isFlat }
            + candidates.filter(\.isFlat)
        return order.first { e in
            let f = e.footprint
            return p.x >= f.x - 4 && p.x <= f.maxX + 4 && p.z >= f.z - 4 && p.z <= f.maxZ + 4
        }
    }

    private var accessibilitySummary: String {
        let shown = entries.filter { !$0.isGhost }.map(\.name)
        let size = "\(room.unitSystem.roomLength(Double(room.widthCm))) by \(room.unitSystem.roomLength(Double(room.lengthCm)))"
        return "Floor plan, \(size), showing " + (shown.isEmpty ? "an empty room" : shown.joined(separator: ", "))
    }
}

/// Converts between room centimetres and points in the plan view.
private struct PlanMap {
    let scale: Double
    let origin: CGPoint
    let roomRect: CGRect

    init(size: CGSize, room: Room) {
        let W = Double(room.widthCm), L = Double(room.lengthCm)
        scale = min(size.width / W, size.height / L)
        origin = CGPoint(x: (size.width - W * scale) / 2, y: (size.height - L * scale) / 2)
        roomRect = CGRect(x: origin.x, y: origin.y, width: W * scale, height: L * scale)
    }

    func cm(_ point: CGPoint) -> (x: Double, z: Double) {
        ((point.x - origin.x) / scale, (point.y - origin.y) / scale)
    }

    func rect(_ r: FloorRect) -> CGRect {
        CGRect(x: origin.x + r.x * scale, y: origin.y + r.z * scale, width: r.w * scale, height: r.d * scale)
    }
}
