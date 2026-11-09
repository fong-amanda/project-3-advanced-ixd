import Foundation

/// A short message about something the other person just did ("Alex: keep the guitar").
/// Shown as a banner at the top of the screen.
struct ActivityEvent: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
    let status: ItemStatus?

    struct Before {
        var status: ItemStatus
        var suggestion: ItemStatus?
        var owner: Owner
        var askedAt: Date?
    }

    static func describe(item: Item, before: Before, room: Room, me: Role) -> ActivityEvent? {
        let them = me.other
        let who = room.name(of: them)
        let thing = item.name.lowercased()

        if item.status != before.status, item.isDecided, item.decidedBy == them {
            let text: String
            if item.status == .sendToOwner {
                text = SortRules.recipient(of: item) == me ? "\(who) is sending the \(thing) to you" : "\(who) is taking the \(thing)"
            } else {
                text = "\(who): \(item.status.shortLabel.lowercased()) the \(thing)"
            }
            return ActivityEvent(text: text, symbol: item.status.icon, status: item.status)
        }

        if let s = item.suggestion, s != before.suggestion, item.suggestedBy == them {
            return ActivityEvent(text: "\(who) suggests: \(s.label.lowercased()) for the \(thing)",
                                 symbol: "text.bubble", status: nil)
        }

        if item.askTo == me, item.askBy == them, let at = item.askedAt, at != before.askedAt {
            return ActivityEvent(text: "\(who) asked about the \(thing)", symbol: "text.bubble", status: nil)
        }

        if item.owner != before.owner, me == .guest, item.owner == .guest || item.owner == .shared {
            let whose = item.owner == .shared ? "shared" : "yours"
            return ActivityEvent(text: "\(room.name(of: .host)) marked the \(thing) as \(whose)",
                                 symbol: "person", status: nil)
        }
        return nil
    }
}
