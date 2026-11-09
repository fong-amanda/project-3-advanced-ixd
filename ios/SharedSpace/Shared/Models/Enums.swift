import SwiftUI

/// Which side of a room the current person is on.
enum Role: String, Codable, CaseIterable, Sendable {
    case host, guest

    var other: Role { self == .host ? .guest : .host }
}

/// Who an item belongs to. Only the owner decides; the other person can suggest.
/// `shared` items can be decided by either person.
enum Owner: String, Codable, CaseIterable, Sendable {
    case unassigned, host, guest, shared
}

/// The single Sort decision for an item.
enum ItemStatus: String, Codable, CaseIterable, Sendable {
    case undecided
    case keep          // stays in this room
    case keepMove      // kept, but moved to another part of the house
    case sendToOwner   // goes back to its owner ("Send to me")
    case letGo         // donate, sell or recycle

    /// The decisions a person can pick (everything except `undecided`).
    static let decisions: [ItemStatus] = [.keep, .keepMove, .sendToOwner, .letGo]

    /// True when the item leaves this room and should disappear from Redesign.
    /// "Keep, but move" intentionally stays in Redesign (product decision, Nov 2026).
    var leavesRoom: Bool { self == .sendToOwner || self == .letGo }

    var icon: String {
        switch self {
        case .undecided: "circle.dashed"
        case .keep: "house"
        case .keepMove: "arrow.right.circle"
        case .sendToOwner: "shippingbox"
        case .letGo: "heart"
        }
    }

    var color: Color {
        switch self {
        case .undecided: .ssNone
        case .keep: .ssKeep
        case .keepMove: .ssMove
        case .sendToOwner: .ssSend
        case .letGo: .ssLetGo
        }
    }

    var softColor: Color {
        switch self {
        case .undecided: .ssSurface2
        case .keep: .ssKeepSoft
        case .keepMove: .ssMoveSoft
        case .sendToOwner: .ssSendSoft
        case .letGo: .ssLetGoSoft
        }
    }

    /// Button label when the person deciding owns the item.
    var buttonLabel: String {
        switch self {
        case .undecided: "Undecided"
        case .keep: "Keep"
        case .keepMove: "Keep, move it"
        case .sendToOwner: "Send to me"
        case .letGo: "Let go"
        }
    }

    /// Longer explanation used on the one-at-a-time cards.
    var explanation: String {
        switch self {
        case .undecided: ""
        case .keep: "It stays where it is"
        case .keepMove: "Keep it, somewhere else in the house"
        case .sendToOwner: "It’ll be packed up for you"
        case .letGo: "Donate, sell or recycle"
        }
    }
}

enum ItemSource: String, Codable, Sendable {
    case scanned, manual
}
