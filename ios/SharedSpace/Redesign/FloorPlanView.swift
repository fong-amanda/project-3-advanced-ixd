import SwiftUI

/// Top-down floor plan of a room and its things. Back wall at the top, like the prototype.
struct FloorPlanView: View {
    let room: Room
    let entries: [PlanEntry]
    var showLabels = true
    /// Draw removed things as dashed outlines (otherwise they're left out).
    var showGhosts = false

    var body: some View {
        Canvas { context, size in
            let W = CGFloat(room.widthCm), L = CGFloat(room.lengthCm)
            let scale = min(size.width / W, size.height / L)
            let origin = CGPoint(x: (size.width - W * scale) / 2, y: (size.height - L * scale) / 2)
            let roomRect = CGRect(x: origin.x, y: origin.y, width: W * scale, height: L * scale)

            context.fill(Path(roomRect), with: .color(.ssSurface))

            // Flat things (rugs) first, then ghosts, then everything standing on the floor.
            let ordered = entries.filter { $0.isFlat && !$0.isGhost }
                + entries.filter { $0.isGhost && showGhosts }
                + entries.filter { !$0.isFlat && !$0.isGhost }

            for entry in ordered {
                var c = context
                c.translateBy(x: origin.x + entry.xCm * scale, y: origin.y + entry.zCm * scale)
                c.rotate(by: .degrees(entry.yawDeg))
                let rect = CGRect(x: -entry.widthCm * scale / 2, y: -entry.depthCm * scale / 2,
                                  width: entry.widthCm * scale, height: entry.depthCm * scale)
                let shape = Path(roundedRect: rect, cornerRadius: 3)
                draw(entry, shape: shape, in: &c)

                if showLabels && !entry.isFlat && rect.width > 44 && rect.height > 20 {
                    c.rotate(by: .degrees(-entry.yawDeg))
                    let text = Text(entry.name)
                        .font(.system(size: min(12, rect.width / 7)))
                        .foregroundStyle(entry.isGhost ? Color.ssMuted : Color.ssInk)
                    c.draw(text, at: .zero)
                }
            }

            context.stroke(Path(roomRect), with: .color(.ssInk), lineWidth: 3)
        }
        .aspectRatio(CGFloat(room.widthCm) / CGFloat(max(room.lengthCm, 1)), contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private func draw(_ entry: PlanEntry, shape: Path, in c: inout GraphicsContext) {
        switch entry.style {
        case .normal:
            c.fill(shape, with: .color(entry.isFlat ? Color(hex: entry.colorHex).opacity(0.25) : .ssSurface2))
            c.stroke(shape, with: .color(entry.isFlat ? .clear : .ssLine), lineWidth: 1.5)
        case .moved:
            c.fill(shape, with: .color(.ssSurface2))
            c.stroke(shape, with: .color(.ssInk2), lineWidth: 2)
        case .newPiece:
            c.fill(shape, with: .color(.ssAccentSoft))
            c.stroke(shape, with: .color(.ssAccent), lineWidth: 2)
        case .leaving(let status):
            c.stroke(shape, with: .color(status.color), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        case .hiddenInDesign:
            c.stroke(shape, with: .color(.ssMuted), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
        }
    }

    private var accessibilitySummary: String {
        let shown = entries.filter { !$0.isGhost }.map(\.name)
        return "Floor plan, \(room.widthCm) by \(room.lengthCm) centimetres, showing " +
            (shown.isEmpty ? "an empty room" : shown.joined(separator: ", "))
    }
}
