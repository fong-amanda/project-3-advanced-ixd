import SwiftUI

/// Which side of a room the current person is on.
enum Role: String, Codable, CaseIterable, Sendable {
    case host, guest

    var other: Role { self == .host ? .guest : .host }
}

/// Who an item belongs to. Only the owner decides; the other person can suggest.
/// `shared` ("Both") and `unassigned` items can be decided by either person.
enum Owner: String, Codable, CaseIterable, Sendable {
    case unassigned, host, guest, shared

    init(_ role: Role) { self = role == .host ? .host : .guest }

    /// The person, when this is one person's thing.
    var role: Role? {
        switch self {
        case .host: .host
        case .guest: .guest
        case .shared, .unassigned: nil
        }
    }
}

/// The single Sort decision for an item.
enum ItemStatus: String, Codable, CaseIterable, Sendable {
    case undecided
    case keep          // stays in this room
    case keepMove      // legacy (before Nov 2026): kept, but moved elsewhere. No longer offered.
    case sendToOwner   // goes back to its owner ("Send it to me")
    case letGo         // donate or sell
    case toss          // throw it out
    case unsure        // "Not sure": a recorded answer, but the thing stays where it is

    /// The decisions the owner can pick, in the prototype's order.
    static let decisions: [ItemStatus] = [.keep, .sendToOwner, .letGo, .toss, .unsure]
    /// What someone who doesn't own the thing can suggest ("Not sure" isn't a suggestion).
    static let suggestions: [ItemStatus] = [.keep, .sendToOwner, .letGo, .toss]

    /// True when the item leaves this room: hidden in the room plan, and its floor counts as freed.
    var leavesRoom: Bool { self == .sendToOwner || self == .letGo || self == .toss }

    var icon: String {
        switch self {
        case .undecided: "circle.dashed"
        case .keep: "house"
        case .keepMove: "arrow.right.circle"
        case .sendToOwner: "shippingbox"
        case .letGo: "heart"
        case .toss: "trash"
        case .unsure: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .undecided: .undecided
        case .keep: .keep
        case .keepMove: .moveElsewhere
        case .sendToOwner: .send
        case .letGo: .letGo
        case .toss: .toss
        case .unsure: .unsure
        }
    }

    var softColor: Color {
        switch self {
        case .undecided: .surfaceMuted
        case .keep: .keepSoft
        case .keepMove: .moveElsewhereSoft
        case .sendToOwner: .sendSoft
        case .letGo: .letGoSoft
        case .toss: .tossSoft
        case .unsure: .unsureSoft
        }
    }

    /// Full label, used on the one-at-a-time cards ("Keep it here").
    var label: String {
        switch self {
        case .undecided: "Undecided"
        case .keep: "Keep it here"
        case .keepMove: "Keep, but move it"
        case .sendToOwner: "Send it to me"
        case .letGo: "Donate or sell it"
        case .toss: "Throw it out"
        case .unsure: "Not sure"
        }
    }

    /// Short label, used on decision buttons, filters and banners ("Keep").
    var shortLabel: String {
        switch self {
        case .undecided: "Undecided"
        case .keep: "Keep"
        case .keepMove: "Keep, move it"
        case .sendToOwner: "Send"
        case .letGo: "Donate or sell"
        case .toss: "Throw out"
        case .unsure: "Not sure"
        }
    }

    /// Where it stands, for lists and the summary ("Staying").
    var statusLabel: String {
        switch self {
        case .undecided: "Not decided yet"
        case .keep: "Staying"
        case .keepMove: "Moving elsewhere in the house"
        case .sendToOwner: "Going to owner"
        case .letGo: "Donating or selling"
        case .toss: "Throwing out"
        case .unsure: "Not sure yet"
        }
    }

    /// Extra line under a card choice, when it needs one.
    var detail: String? {
        switch self {
        case .sendToOwner: "Packed up and sent to you"
        case .unsure: "Saved as undecided"
        default: nil
        }
    }
}

enum ItemSource: String, Codable, Sendable {
    case scanned, manual
}
