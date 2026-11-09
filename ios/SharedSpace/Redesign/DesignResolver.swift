import Foundation

/// One thing drawn in a plan view.
struct PlanEntry: Identifiable {
    enum Style: Equatable {
        case normal                 // a real item, where it physically is
        case moved                  // a real item, at its new place in this design
        case leaving(ItemStatus)    // Sort says it leaves the room
        case hiddenInDesign         // hidden in this design only; Sort still says it stays
        case newPiece               // a piece placed in this plan
    }

    /// Item id for real things; placement id for placed pieces.
    let id: UUID
    let name: String
    let xCm: Double
    let zCm: Double
    let widthCm: Double
    let depthCm: Double
    let yawDeg: Double
    /// For the 3D view.
    var heightCm: Double?
    let isFlat: Bool
    let colorHex: String
    let style: Style
    /// Set for pieces that need a look ("Overlaps the desk").
    var problem: String?

    var isGhost: Bool {
        switch style {
        case .leaving, .hiddenInDesign: true
        default: false
        }
    }

    var footprint: FloorRect {
        RoomGeometry.footprint(x: xCm, z: zCm, w: widthCm, d: depthCm, yawDeg: yawDeg)
    }

    init(actual item: Item, style: Style = .normal) {
        id = item.id
        name = item.name
        xCm = item.xCm
        zCm = item.zCm
        widthCm = item.widthCm
        depthCm = item.depthCm
        yawDeg = item.yawDeg
        heightCm = item.heightCm
        isFlat = item.category.isFlat
        colorHex = item.category.colorHex
        self.style = style
    }

    init(item: Item, placement: DesignPlacement, style: Style) {
        id = item.id
        name = item.name
        xCm = placement.xCm
        zCm = placement.zCm
        widthCm = item.widthCm
        depthCm = item.depthCm
        yawDeg = placement.yawDeg
        heightCm = item.heightCm
        isFlat = item.category.isFlat
        colorHex = item.category.colorHex
        self.style = style
    }

    init(piece: CatalogPiece, placement: DesignPlacement) {
        id = placement.id
        name = piece.name
        xCm = placement.xCm
        zCm = placement.zCm
        widthCm = piece.w
        depthCm = piece.d
        yawDeg = placement.yawDeg
        heightCm = piece.h
        isFlat = piece.isFlat
        colorHex = piece.colorHex
        style = .newPiece
    }
}

/// Combines the room's items (and their live Sort decisions) with one design's changes.
/// Designs never store Sort decisions, so a later "Donate or sell" in Sort is reflected here at once.
struct ResolvedDesign {
    var entries: [PlanEntry] = []
    /// Items Sort has sent out of the room.
    var leaving: [Item] = []
    /// Items hidden in this design only.
    var hiddenInDesign: [Item] = []
    /// Items this design moved that Sort has since marked as leaving.
    var conflicts: [Item] = []
    /// Placed pieces, with what they are.
    var pieces: [(placement: DesignPlacement, piece: CatalogPiece)] = []

    var problems: [PlanEntry] { entries.filter { $0.problem != nil } }
    var pieceCost: Int { pieces.reduce(0) { $0 + $1.piece.price } }
}

enum DesignResolver {
    /// `design == nil` means "the room as it is now".
    static func resolve(items: [Item], design: Design?, room: Room? = nil) -> ResolvedDesign {
        var result = ResolvedDesign()
        let placements = design?.livePlacements ?? []
        var byItem: [UUID: DesignPlacement] = [:]
        for p in placements { if let id = p.itemId { byItem[id] = p } }

        for item in items {
            let placement = byItem[item.id]
            if item.status.leavesRoom {
                result.leaving.append(item)
                result.entries.append(PlanEntry(actual: item, style: .leaving(item.status)))
                if let placement, !placement.hidden { result.conflicts.append(item) }
            } else if let placement, placement.hidden {
                result.hiddenInDesign.append(item)
                result.entries.append(PlanEntry(actual: item, style: .hiddenInDesign))
            } else if let placement {
                result.entries.append(PlanEntry(item: item, placement: placement, style: .moved))
            } else {
                result.entries.append(PlanEntry(actual: item))
            }
        }

        let kept = result.entries.filter { !$0.isGhost && !$0.isFlat }
        var placed: [PlanEntry] = []
        for p in placements.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            guard let id = p.catalogId, let piece = Catalogue.piece(id, items: items) else { continue }
            result.pieces.append((p, piece))
            placed.append(PlanEntry(piece: piece, placement: p))
        }
        // Problems: through a wall, or on top of something that's staying, or of another piece.
        for i in placed.indices where !placed[i].isFlat {
            let f = placed[i].footprint
            if let room, f.x < -1 || f.z < -1 || f.maxX > Double(room.widthCm) + 1 || f.maxZ > Double(room.lengthCm) + 1
                || !room.shape.contains(f) {
                placed[i].problem = "Goes through a wall"
            } else if let hit = kept.first(where: { f.overlaps($0.footprint, padding: 2) }) {
                placed[i].problem = "Overlaps the \(hit.name.lowercased())"
            } else if let hit = placed.first(where: { $0.id != placed[i].id && !$0.isFlat && f.overlaps($0.footprint, padding: 2) }) {
                placed[i].problem = "Overlaps the \(hit.name.lowercased())"
            }
        }
        result.entries += placed
        return result
    }

    /// "3 things marked Donate or sell are hidden" / "4 things that are leaving are hidden".
    static func hiddenSummary(_ leaving: [Item]) -> String? {
        guard !leaving.isEmpty else { return nil }
        let total = leaving.count
        let noun = total == 1 ? "1 thing" : "\(total) things"
        let verb = total == 1 ? "is" : "are"
        let kinds = Set(leaving.map(\.status))
        if kinds.count == 1, let only = kinds.first { return "\(noun) marked \(only.shortLabel) \(verb) hidden" }
        return "\(noun) leaving the room \(verb) hidden"
    }
}
