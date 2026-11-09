import Foundation

/// Who may decide what, and how decisions read. Used by Items, Room plan and the banners.
enum SortRules {
    /// Can `role` set this item's decision directly (rather than only suggesting)?
    ///
    /// * The owner decides. Things that belong to both people, or to nobody yet, either person.
    /// * Someone else's thing: you can suggest, or the owner can ask you.
    static func canDecide(_ item: Item, as role: Role, in room: Room) -> Bool {
        switch item.owner {
        case .unassigned, .shared: true
        case .host: role == .host
        case .guest: role == .guest
        }
    }

    /// The other person asked `me` about this, and I haven't answered with a suggestion yet.
    static func isAskedOf(_ item: Item, me: Role) -> Bool {
        item.askTo == me && !(item.suggestion != nil && item.suggestedBy == me)
    }

    /// Not decided, and it's someone else's call.
    static func isWaiting(_ item: Item, me: Role, in room: Room) -> Bool {
        !item.isDecided && !canDecide(item, as: me, in: room)
    }

    /// Order in the list. 0: yours to decide. 1: you were asked. 2: waiting for the other person. 3: decided.
    static func rank(_ item: Item, me: Role, in room: Room) -> Int {
        if !item.isDecided && canDecide(item, as: me, in: room) { return 0 }
        if !item.isDecided && isAskedOf(item, me: me) { return 1 }
        if !item.isDecided { return 2 }
        return 3
    }

    /// Things that need `me`: undecided things I decide, plus things I was asked about.
    static func needsMe(_ item: Item, me: Role, in room: Room) -> Bool { rank(item, me: me, in: room) <= 1 }

    /// The one-at-a-time queue: my undecided things, and things I was asked about.
    /// Things skipped with "Skip for now" go to the back of the line.
    static func queue(_ items: [Item], me: Role, in room: Room, skipped: [UUID]) -> [Item] {
        let q = items.filter { item in
            let mine = canDecide(item, as: me, in: room) && !item.isDecided
            let asked = isAskedOf(item, me: me) && !(item.isDecided && item.owner == Owner(me))
            return mine || asked
        }
        return q.filter { !skipped.contains($0.id) } + q.filter { skipped.contains($0.id) }
    }

    /// Who receives an item marked "Send it to me".
    static func recipient(of item: Item) -> Role {
        item.owner.role ?? item.decidedBy ?? .host
    }

    /// Status line under an item, from `me`'s point of view, using real names.
    static func statusText(_ item: Item, room: Room, me: Role) -> String {
        switch item.status {
        case .sendToOwner:
            let to = recipient(of: item)
            return to == me ? "Coming to you" : "Going to \(room.name(of: to))"
        case .keepMove:
            if let place = item.moveDestination, !place.isEmpty { return "Moving to \(place)" }
            return item.status.statusLabel
        default:
            return item.status.statusLabel
        }
    }

    /// "Sam’s", "Shared" — or nil when it's yours (or nobody's yet), which needs no tag.
    static func ownerLabel(_ item: Item, room: Room, me: Role) -> String? {
        switch item.owner {
        case .unassigned: nil
        case .shared: "Shared"
        case .host, .guest: item.owner == Owner(me) ? nil : possessive(room.name(of: item.owner.role!))
        }
    }

    static func possessive(_ name: String) -> String {
        name.hasSuffix("s") ? "\(name)’" : "\(name)’s"
    }

    /// Items that belong (in whole or part) to `role`.
    static func items(_ items: [Item], belongingTo role: Role) -> [Item] {
        items.filter { $0.owner == .shared || $0.owner == Owner(role) }
    }

    /// One line that says where things stand, for the person looking:
    /// "2 for you to decide · 1 question for you · 3 waiting for Alex".
    static func overview(_ items: [Item], me: Role, in room: Room) -> String? {
        guard !items.isEmpty else { return nil }
        let mine = items.filter { !$0.isDecided && canDecide($0, as: me, in: room) }.count
        let asks = items.filter { !$0.isDecided && isAskedOf($0, me: me) }.count
        let theirs = items.filter { isWaiting($0, me: me, in: room) }.count
        var parts: [String] = []
        if mine > 0 { parts.append("\(mine) for you to decide") }
        if asks > 0 { parts.append("\(asks) question\(asks == 1 ? "" : "s") for you") }
        if theirs > 0 { parts.append("\(theirs) waiting for \(room.name(of: me.other))") }
        return parts.isEmpty ? "Everything’s decided" : parts.joined(separator: " · ")
    }
}

/// Counts for the summary.
struct SortProgress {
    var total = 0
    var decided = 0
    var byStatus: [ItemStatus: Int] = [:]
    /// Floor area (cm²) freed by items that leave the room.
    var freedCm2 = 0.0

    init(_ items: [Item]) {
        total = items.count
        for item in items {
            byStatus[item.status, default: 0] += 1
            if item.isDecided { decided += 1 }
            if item.status.leavesRoom && !item.category.isFlat {
                freedCm2 += item.widthCm * item.depthCm
            }
        }
    }

    var undecided: Int { total - decided }
    var leaving: Int { ItemStatus.allCases.filter(\.leavesRoom).reduce(0) { $0 + (byStatus[$1] ?? 0) } }
    var isComplete: Bool { total > 0 && undecided == 0 }
}
