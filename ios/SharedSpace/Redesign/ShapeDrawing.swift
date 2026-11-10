import SwiftUI

/// Maps room centimetres to points in a view, for plans and the shape editor.
struct PlanTransform {
    let scale: Double
    let origin: CGPoint

    /// Fits a W×L room into `size`, centred.
    init(fitting size: CGSize, width W: Double, length L: Double) {
        scale = min(size.width / max(W, 1), size.height / max(L, 1))
        origin = CGPoint(x: (size.width - W * scale) / 2, y: (size.height - L * scale) / 2)
    }

    init(scale: Double, origin: CGPoint) {
        self.scale = scale
        self.origin = origin
    }

    func point(_ x: Double, _ z: Double) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + z * scale) }
    func cm(_ p: CGPoint) -> (x: Double, z: Double) { ((p.x - origin.x) / scale, (p.y - origin.y) / scale) }
    func rect(_ r: FloorRect) -> CGRect { CGRect(x: origin.x + r.x * scale, y: origin.y + r.z * scale, width: r.w * scale, height: r.d * scale) }
}

/// Drawing a room's outline, doors and windows (shared by the floor plan and the shape editor).
enum ShapeDrawing {
    static func outline(_ shape: RoomShape, _ t: PlanTransform) -> Path {
        var path = Path()
        for (i, c) in shape.corners.enumerated() {
            let p = t.point(c.x, c.z)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    static func drawFloor(_ shape: RoomShape, _ t: PlanTransform, fill: Color, in c: inout GraphicsContext) {
        c.fill(outline(shape, t), with: .color(fill))
    }

    static func drawWalls(_ shape: RoomShape, _ t: PlanTransform, in c: inout GraphicsContext) {
        c.stroke(outline(shape, t), with: .color(.textPrimary),
                 style: StrokeStyle(lineWidth: Stroke.heavy, lineJoin: .round))
    }

    /// Doors: a gap in the wall, the open leaf and its swing. Windows: a light gap with a glass line.
    static func drawOpenings(_ shape: RoomShape, _ t: PlanTransform, selected: UUID? = nil, handles: Bool = false,
                             in c: inout GraphicsContext) {
        for o in shape.openings {
            guard let p = shape.placement(of: o) else { continue }
            let half = p.width / 2
            let a = (x: p.center.x - p.along.x * half, z: p.center.z - p.along.z * half)
            let b = (x: p.center.x + p.along.x * half, z: p.center.z + p.along.z * half)
            var gap = Path()
            gap.move(to: t.point(a.x, a.z))
            gap.addLine(to: t.point(b.x, b.z))
            if o.kind == .window {
                c.stroke(gap, with: .color(.tintSlate), lineWidth: Stroke.heavy * 2.4)
                c.stroke(gap, with: .color(.send), lineWidth: Stroke.hairline)
            } else {
                c.stroke(gap, with: .color(.surface), lineWidth: Stroke.heavy * 2.4)
                let n = shape.inwardNormal(p.edge)
                let side = o.swingsIn ? 1.0 : -1.0
                let hinge = o.hingeAtEnd ? b : a
                let free = o.hingeAtEnd ? a : b
                let leafEnd = (x: hinge.x + n.x * side * p.width, z: hinge.z + n.z * side * p.width)
                var leaf = Path()
                leaf.move(to: t.point(hinge.x, hinge.z))
                leaf.addLine(to: t.point(leafEnd.x, leafEnd.z))
                c.stroke(leaf, with: .color(.iconNeutral), style: StrokeStyle(lineWidth: Stroke.bold, lineCap: .round))
                var arc = Path()
                arc.move(to: t.point(leafEnd.x, leafEnd.z))
                arc.addQuadCurve(to: t.point(free.x, free.z),
                                 control: t.point(free.x + n.x * side * p.width, free.z + n.z * side * p.width))
                c.stroke(arc, with: .color(.textSecondary), style: StrokeStyle(lineWidth: Stroke.hairline, dash: Stroke.dotted))
            }
            if handles {
                let on = o.id == selected
                let center = t.point(p.center.x, p.center.z)
                let r = on ? Size.tick / 2.4 : Size.tick / 3
                let dot = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                c.fill(dot, with: .color(o.kind == .door ? .iconNeutral : .send))
                c.stroke(dot, with: .color(on ? .textPrimary : .surface), lineWidth: Stroke.bold)
            }
        }
    }
}
