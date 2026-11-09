import Foundation

@MainActor
enum DesignActions {
    /// Creates the next option (A, B, C). A new option copies the changes of `copying`, if given;
    /// otherwise it starts as the room exactly as it is.
    @discardableResult
    static func createDesign(in room: Room, existing: [Design], copying source: Design?, sync: SyncEngine) -> Design? {
        let letters = ["A", "B", "C"]
        guard existing.count < Design.maxPerRoom,
              let index = letters.indices.first(where: { i in !existing.contains { $0.name == "Option \(letters[i])" } })
        else { return nil }
        let design = Design(room: room, name: "Option \(letters[index])", sortOrder: index)
        sync.insert(design)
        sync.save(design)
        for p in source?.livePlacements ?? [] {
            let copy = DesignPlacement(design: design, itemId: p.itemId, catalogId: p.catalogId,
                                       xCm: p.xCm, zCm: p.zCm, yawDeg: p.yawDeg, hidden: p.hidden)
            sync.insert(copy)
            sync.save(copy)
        }
        return design
    }

    /// Drops a design's change for an item (e.g. after Sort marked it Let go).
    static func clearPlacement(for item: Item, in design: Design, sync: SyncEngine) {
        for p in design.livePlacements where p.itemId == item.id {
            p.deletedAt = .now
            sync.save(p)
        }
    }
}
