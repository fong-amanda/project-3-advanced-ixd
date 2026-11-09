import Foundation

/// The writes Items makes. Every screen (list, cards, item sheet) goes through these so the
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
            item.moveDestination = nil
            item.pickupDate = nil
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

    /// Asks the other person what should happen to this thing. It shows up in their queue.
    static func ask(about item: Item, as me: Role, sync: SyncEngine) {
        item.askBy = me
        item.askTo = me.other
        item.askedAt = .now
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

    /// Moves an item's number on a room photo (fractions of the photo's size).
    static func setPin(_ point: CGPoint, photo: Int, for item: Item, sync: SyncEngine) {
        item.pinX = min(max(point.x, 0.02), 0.98)
        item.pinY = min(max(point.y, 0.02), 0.98)
        item.pinPhoto = photo
        sync.save(item)
    }

    /// Adds a thing to the room, placed in a free spot on the floor and, if given, pinned on a photo.
    @discardableResult
    static func addItem(name: String, category: ItemCategory, owner: Owner, pin: CGPoint? = nil, photo: Int = 0,
                        to room: Room, existing: [Item], sync: SyncEngine) -> Item {
        let size = category.defaultSize
        let spot = RoomGeometry.findSpot(w: size.w, d: size.d, avoiding: RoomGeometry.obstacles(existing),
                                         roomWidth: Double(room.widthCm), roomLength: Double(room.lengthCm), inside: room.shape)
        let order = (existing.map(\.sortOrder).max() ?? -1) + 1
        let item = Item(room: room, name: name, category: category, source: .manual,
                        position: (spot.x, 0, spot.z), sortOrder: order)
        item.owner = owner
        if let pin {
            item.pinX = pin.x
            item.pinY = pin.y
            item.pinPhoto = photo
        }
        sync.insert(item)
        sync.save(item)
        return item
    }

    /// Who new things belong to by default: the guest when the room is full of their things.
    static func defaultOwner(in room: Room, items: [Item]) -> Owner {
        guard room.hasGuest else { return .host }
        let guests = items.filter { $0.owner == .guest }.count
        return guests * 2 > items.count ? .guest : .host
    }

    static func remove(_ item: Item, sync: SyncEngine) {
        item.deletedAt = .now
        sync.save(item)
    }
}
