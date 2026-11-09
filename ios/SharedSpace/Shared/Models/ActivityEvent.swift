import Foundation

/// A short message about something the other person just did ("Sam is taking the guitar").
/// Shown as a banner at the top of the screen.
struct ActivityEvent: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
    let status: ItemStatus?

    static func describe(
        item: Item,
        before: (status: ItemStatus, suggestion: ItemStatus?, owner: Owner),
        room: Room,
        me: Role
    ) -> ActivityEvent? {
        let them = me.other
        let who = room.name(of: them)
        let thing = item.name.lowercased()

        if item.status != before.status, item.status != .undecided, item.decidedBy == them {
            let text: String
            switch item.status {
            case .keep:
                text = "\(who) is keeping the \(thing) in the room"
            case .keepMove:
                if let place = item.moveDestination, !place.isEmpty {
                    text = "\(who) is keeping the \(thing) and moving it to \(place.lowercased())"
                } else {
                    text = "\(who) is keeping the \(thing) somewhere else in the house"
                }
            case .sendToOwner:
                let recipient = SortRules.recipient(of: item)
                text = recipient == me ? "\(who) is sending the \(thing) to you" : "\(who) is taking the \(thing)"
            case .letGo:
                text = "\(who) is letting go of the \(thing)"
            case .undecided:
                return nil
            }
            return ActivityEvent(text: text, symbol: item.status.icon, status: item.status)
        }

        if let s = item.suggestion, s != before.suggestion, item.suggestedBy == them {
            return ActivityEvent(text: "\(who) suggests: \(s.buttonLabel.lowercased()) for the \(thing)",
                                 symbol: "text.bubble", status: nil)
        }

        if item.owner != before.owner, me == .guest, item.owner == .guest || item.owner == .shared {
            let whose = item.owner == .shared ? "shared" : "yours"
            return ActivityEvent(text: "\(room.name(of: .host)) marked the \(thing) as \(whose)",
                                 symbol: "person", status: nil)
        }
        return nil
    }
}
