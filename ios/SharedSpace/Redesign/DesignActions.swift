import Foundation

/// The writes Room plan makes. Only the host edits plans; locked versions are never changed.
@MainActor
enum DesignActions {
    /// The plan the host edits ("Proposed layout"): the first unlocked design, created if needed.
    static func workingDesign(in room: Room, existing: [Design], sync: SyncEngine) -> Design {
        if let open = existing.filter({ !$0.locked }).min(by: { $0.sortOrder < $1.sortOrder }) { return open }
        let design = Design(room: room, name: Design.workingName, sortOrder: 0)
        sync.insert(design)
        sync.save(design)
        return design
    }

    /// Places a piece, in the chosen free zone (turned to fit if needed) or the best free spot.
    @discardableResult
    static func addPiece(_ piece: CatalogPiece, to design: Design, room: Room, items: [Item], zone: FreeZone?,
                         sync: SyncEngine) -> DesignPlacement {
        let W = Double(room.widthCm), L = Double(room.lengthCm)
        var x = W / 2, z = L * 0.55, yaw = 0.0
        if !piece.isFlat {
            if let zone {
                let r = zone.rect
                if (piece.w > r.w && piece.d <= r.w) || (r.d > r.w * 1.3 && piece.w > piece.d * 1.3) { yaw = 90 }
                x = ((r.x + r.w / 2) / 5).rounded() * 5
                z = ((r.z + r.d / 2) / 5).rounded() * 5
                let f = RoomGeometry.footprint(x: x, z: z, w: piece.w, d: piece.d, yawDeg: yaw)
                if f.x < 0 { x -= f.x }
                if f.z < 0 { z -= f.z }
                if f.maxX > W { x -= f.maxX - W }
                if f.maxZ > L { z -= f.maxZ - L }
            } else {
                let resolved = DesignResolver.resolve(items: items, design: design, room: room)
                let obstacles = resolved.entries.filter { !$0.isGhost && !$0.isFlat }.map(\.footprint)
                let spot = RoomGeometry.findSpot(w: piece.w, d: piece.d, avoiding: obstacles, roomWidth: W, roomLength: L,
                                                 inside: room.shape)
                x = spot.x
                z = spot.z
            }
        }
        let placement = DesignPlacement(design: design, catalogId: piece.id, xCm: x.rounded(), zCm: z.rounded(), yawDeg: yaw)
        sync.insert(placement)
        sync.save(placement)
        touch(design, sync: sync)
        return placement
    }

    static func move(_ placement: DesignPlacement, x: Double, z: Double, sync: SyncEngine) {
        placement.xCm = x
        placement.zCm = z
        sync.save(placement)
    }

    static func turn(_ placement: DesignPlacement, sync: SyncEngine) {
        placement.yawDeg = (placement.yawDeg + 90).truncatingRemainder(dividingBy: 360)
        sync.save(placement)
    }

    static func remove(_ placement: DesignPlacement, sync: SyncEngine) {
        placement.deletedAt = .now
        sync.save(placement)
    }

    /// Drops a design's change for an item (e.g. after Sort marked it as leaving).
    static func clearPlacement(for item: Item, in design: Design, sync: SyncEngine) {
        for p in design.livePlacements where p.itemId == item.id {
            p.deletedAt = .now
            sync.save(p)
        }
    }

    /// "Save a version": a locked copy named "Version N".
    @discardableResult
    static func saveVersion(of design: Design, room: Room, existing: [Design], sync: SyncEngine) -> Design {
        let n = existing.filter { $0.locked && $0.name.hasPrefix("Version") }.count + 1
        return snapshot(design, named: "Version \(n)", room: room, existing: existing, sync: sync)
    }

    /// "Share plan with Alex": locks a copy (unless it's already locked) and points the room at it.
    @discardableResult
    static func share(_ design: Design, room: Room, existing: [Design], sync: SyncEngine) -> Design {
        let shared: Design
        if design.locked {
            shared = design
        } else {
            let n = existing.filter { $0.locked && $0.name.hasPrefix("Shared") }.count + 1
            shared = snapshot(design, named: "Shared \(n)", room: room, existing: existing, sync: sync)
        }
        room.sharedDesignId = shared.id
        sync.save(room)
        return shared
    }

    /// "Continue from this version": copies a saved version's pieces into the working plan.
    static func continueFrom(_ version: Design, room: Room, existing: [Design], sync: SyncEngine) -> Design {
        let working = workingDesign(in: room, existing: existing, sync: sync)
        for p in working.livePlacements { p.deletedAt = .now; sync.save(p) }
        copyPlacements(from: version, to: working, sync: sync)
        touch(working, sync: sync)
        return working
    }

    private static func snapshot(_ design: Design, named name: String, room: Room, existing: [Design], sync: SyncEngine) -> Design {
        let order = (existing.map(\.sortOrder).max() ?? 0) + 1
        let copy = Design(room: room, name: name, sortOrder: order)
        copy.locked = true
        sync.insert(copy)
        sync.save(copy)
        copyPlacements(from: design, to: copy, sync: sync)
        return copy
    }

    private static func copyPlacements(from source: Design, to target: Design, sync: SyncEngine) {
        for p in source.livePlacements {
            let copy = DesignPlacement(design: target, itemId: p.itemId, catalogId: p.catalogId,
                                       xCm: p.xCm, zCm: p.zCm, yawDeg: p.yawDeg, hidden: p.hidden)
            sync.insert(copy)
            sync.save(copy)
        }
    }

    private static func touch(_ design: Design, sync: SyncEngine) {
        sync.save(design)
    }
}
