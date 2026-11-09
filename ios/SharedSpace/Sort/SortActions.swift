import Foundation

/// The writes Sort makes. Every screen (list, cards, detail) goes through these so the
/// owner-decides / others-suggest rule is applied the same way everywhere.
@MainActor
enum SortActions {
    /// Decide (if allowed) or suggest (if not). Tapping the current choice again clears it.
    static func choose(_ status: ItemStatus, for item: Item, as me: Role, in room: Room, sync: SyncEngine) {
        if SortRules.canDecide(item, as: me, in: room) {
            let new: ItemStatus = item.status == status ? .undecided : status
            item.status = new
            item.decidedBy = new == .undecided ? nil : me
            item.decidedAt = new == .undecided ? nil : .now
            item.suggestion = nil
            item.suggestedBy = nil
            item.suggestedAt = nil
            if new != .keepMove { item.moveDestination = nil }
            if new != .sendToOwner { item.pickupDate = nil }
        } else if item.suggestion == status && item.suggestedBy == me {
            item.suggestion = nil
            item.suggestedBy = nil
            item.suggestedAt = nil
        } else {
            item.suggestion = status
            item.suggestedBy = me
            item.suggestedAt = .now
        }
        sync.save(item)
    }

    /// Changing who owns something clears its decision (the new owner decides).
    static func setOwner(_ owner: Owner, for item: Item, sync: SyncEngine) {
        guard item.owner != owner else { return }
        item.owner = owner
        item.status = .undecided
        item.decidedBy = nil
        item.decidedAt = nil
        item.moveDestination = nil
        item.pickupDate = nil
        sync.save(item)
    }

    static func setNote(_ text: String, for item: Item, as me: Role, sync: SyncEngine) {
        let note = text.trimmed
        guard note != item.note else { return }
        item.note = note
        item.noteBy = note.isEmpty ? nil : me
        sync.save(item)
    }

    static func setMoveDestination(_ text: String, for item: Item, sync: SyncEngine) {
        let place = text.trimmed
        item.moveDestination = place.isEmpty ? nil : place
        sync.save(item)
    }

    static func setPickupDate(_ date: Date?, for item: Item, sync: SyncEngine) {
        item.pickupDate = date
        sync.save(item)
    }

    /// Who may set the pickup date: whoever the item is going to (or the host deciding for the guest).
    static func canSetPickup(_ item: Item, as me: Role, in room: Room) -> Bool {
        item.status == .sendToOwner &&
            (SortRules.recipient(of: item) == me || (me == .host && !room.guestHasJoined))
    }

    /// Adds a manually entered thing to the room, placed in a free spot on the floor.
    @discardableResult
    static func addItem(name: String, category: ItemCategory, to room: Room, existing: [Item], sync: SyncEngine) -> Item {
        let size = category.defaultSize
        let spot = RoomGeometry.findSpot(w: size.w, d: size.d, avoiding: RoomGeometry.obstacles(existing),
                                         roomWidth: Double(room.widthCm), roomLength: Double(room.lengthCm))
        let order = (existing.map(\.sortOrder).max() ?? -1) + 1
        let item = Item(room: room, name: name, category: category, source: .manual,
                        position: (spot.x, 0, spot.z), sortOrder: order)
        sync.insert(item)
        sync.save(item)
        return item
    }

    static func remove(_ item: Item, sync: SyncEngine) {
        item.deletedAt = .now
        sync.save(item)
    }
}
