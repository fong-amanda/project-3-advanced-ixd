import Foundation

/// One thing drawn in a design view (floor plan now, dollhouse and AR later).
struct PlanEntry: Identifiable {
    enum Style: Equatable {
        case normal                 // a real item, where it physically is
        case moved                  // a real item, at its new place in this design
        case leaving(ItemStatus)    // Sort says it leaves the room (Send to owner / Let go)
        case hiddenInDesign         // hidden in this design only; Sort still says it stays
        case newPiece               // new furniture from the catalogue
    }

    let id: UUID
    let name: String
    let xCm: Double
    let zCm: Double
    let widthCm: Double
    let depthCm: Double
    let yawDeg: Double
    let isFlat: Bool
    let colorHex: String
    let style: Style

    /// Ghosts are shown only when the person asks to see removed things.
    var isGhost: Bool {
        switch style {
        case .leaving, .hiddenInDesign: true
        default: false
        }
    }

    init(actual item: Item, style: Style = .normal) {
        id = item.id
        name = item.name
        xCm = item.xCm
        zCm = item.zCm
        widthCm = item.widthCm
        depthCm = item.depthCm
        yawDeg = item.yawDeg
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
        isFlat = item.category.isFlat
        colorHex = item.category.colorHex
        self.style = style
    }
}

/// Combines the room's items (and their live Sort decisions) with one design's changes.
/// Designs never store Sort decisions, so a later "Let go" in Sort is reflected here at once.
struct ResolvedDesign {
    var entries: [PlanEntry] = []
    /// Items Sort has sent out of the room.
    var leaving: [Item] = []
    /// Items hidden in this design only.
    var hiddenInDesign: [Item] = []
    /// Items this design moved that Sort has since marked as leaving.
    var conflicts: [Item] = []
}

enum DesignResolver {
    /// `design == nil` means "the room as it is now".
    static func resolve(items: [Item], design: Design?) -> ResolvedDesign {
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
        return result
    }

    /// "3 items marked Let go are hidden" / "4 items are hidden: 3 marked Let go, 1 marked Send to owner".
    static func hiddenSummary(_ leaving: [Item]) -> String? {
        guard !leaving.isEmpty else { return nil }
        let letGo = leaving.filter { $0.status == .letGo }.count
        let send = leaving.filter { $0.status == .sendToOwner }.count
        let total = leaving.count
        let noun = total == 1 ? "1 item" : "\(total) items"
        let verb = total == 1 ? "is" : "are"
        if send == 0 { return "\(noun) marked Let go \(verb) hidden" }
        if letGo == 0 { return "\(noun) marked Send to owner \(verb) hidden" }
        return "\(noun) \(verb) hidden: \(letGo) marked Let go, \(send) marked Send to owner"
    }
}
