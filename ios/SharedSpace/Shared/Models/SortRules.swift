import Foundation

/// Who may decide what, and how decisions read. Used by Sort, Redesign and the banners.
enum SortRules {
    /// Can `role` set this item's decision directly (rather than only suggesting)?
    ///
    /// * The owner decides. Shared items: either person.
    /// * Until the guest joins (or when sorting solo), the host can decide for them.
    /// * Unassigned items need an owner first.
    static func canDecide(_ item: Item, as role: Role, in room: Room) -> Bool {
        switch item.owner {
        case .unassigned: false
        case .shared: true
        case .host: role == .host
        case .guest: role == .guest || (role == .host && !room.guestHasJoined)
        }
    }

    /// True when the host is deciding on the guest's behalf ("Decide for Sam").
    static func isDecidingForGuest(_ item: Item, as role: Role, in room: Room) -> Bool {
        item.owner == .guest && role == .host && !room.guestHasJoined
    }

    /// Who receives an item marked "Send to me".
    static func recipient(of item: Item) -> Role {
        switch item.owner {
        case .host: .host
        case .guest: .guest
        case .shared, .unassigned: item.decidedBy ?? .host
        }
    }

    /// Status line under an item, from `me`'s point of view, using real names.
    static func statusText(_ item: Item, room: Room, me: Role) -> String {
        switch item.status {
        case .undecided:
            return "Not decided yet"
        case .keep:
            return "Staying in the room"
        case .keepMove:
            if let place = item.moveDestination, !place.isEmpty { return "Moving to \(place)" }
            return "Moving elsewhere in the house"
        case .sendToOwner:
            let to = recipient(of: item)
            var text = to == me ? "Coming to you" : "Going to \(room.name(of: to))"
            if let date = item.pickupDate {
                text += ", pickup \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
            }
            return text
        case .letGo:
            return "Letting go"
        }
    }

    /// "Yours", "Sam’s", "Shared" or "Whose is it?".
    static func ownerLabel(_ item: Item, room: Room, me: Role) -> String {
        switch item.owner {
        case .unassigned: "Whose is it?"
        case .shared: "Shared"
        case .host, .guest:
            item.owner.rawValue == me.rawValue ? "Yours" : possessive(room.name(of: item.owner == .host ? .host : .guest))
        }
    }

    static func possessive(_ name: String) -> String {
        name.hasSuffix("s") ? "\(name)’" : "\(name)’s"
    }

    /// Items that belong (in whole or part) to `role`.
    static func items(_ items: [Item], belongingTo role: Role) -> [Item] {
        items.filter { $0.owner == .shared || $0.owner.rawValue == role.rawValue }
    }
}

/// Counts for progress bars.
struct SortProgress {
    var total = 0
    var decided = 0
    var byStatus: [ItemStatus: Int] = [:]
    /// Floor area (m²) freed by items that leave the room.
    var freedM2 = 0.0

    init(_ items: [Item]) {
        total = items.count
        for item in items {
            byStatus[item.status, default: 0] += 1
            if item.isDecided { decided += 1 }
            if item.status.leavesRoom && !item.category.isFlat {
                freedM2 += item.widthCm * item.depthCm / 10_000
            }
        }
    }

    var undecided: Int { total - decided }
    var isComplete: Bool { total > 0 && undecided == 0 }
    func fraction(_ status: ItemStatus) -> Double { total == 0 ? 0 : Double(byStatus[status] ?? 0) / Double(total) }
}
