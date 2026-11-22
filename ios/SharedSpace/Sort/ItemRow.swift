import SwiftUI

/// One thing in the Items list: thumbnail (with its photo number), name, and where it stands.
struct ItemRow: View {
    let item: Item
    let room: Room
    let me: Role
    var number: Int?
    /// nil = not selecting; true/false = selected or not in "Select" mode.
    var selection: Bool?
    /// The trailing "opens" chevron. Off when the list draws its own expand button beside the row.
    var showsChevron = true

    var body: some View {
        HStack(spacing: Space.m) {
            ItemThumb(item: item)
                .overlay(alignment: .bottomTrailing) {
                    if let number {
                        NumberBadge(number: number, size: Size.badgeSmall).offset(x: Space.xs, y: Space.xs)
                    }
                }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(item.name).textRole(.bodyStrong)
                FlowLayout(spacing: Space.xs) { subline }
                    // A decision tag is a little taller than "Undecided": keep room for it, so
                    // choosing a decision never changes the row's height.
                    .frame(minHeight: tagHeight, alignment: .leading)
            }
            Spacer(minLength: 0)
            if let selection {
                TickBadge(isOn: selection)
            } else if showsChevron {
                RowChevron()
            }
        }
        .padding(.vertical, Space.m)
        .frame(minHeight: Size.row)
        .accessibilityElement(children: .ignore)
        // "3, Guitar, going to Sam", then the details the row shows under the name.
        .accessibilityLabel((number.map { "\($0), " } ?? "") + SortRules.accessibilityName(item, room: room))
        .accessibilityValue(spokenDetails)
        .accessibilityAddTraits(selection == true ? .isSelected : [])
    }

    /// Everything else the row shows, in words: who decided, who's being asked, whose it is.
    private var spokenDetails: String {
        var parts: [String] = []
        let asked = SortRules.isAskedOf(item, me: me)
        if item.isDecided {
            if let by = decidedByOther { parts.append("decided by \(by)") }
        } else if asked, let by = item.askBy {
            parts.append("\(room.name(of: by)) asked you")
        } else if item.askBy == me, let to = item.askTo {
            parts.append("asked \(room.name(of: to))")
        } else if let owner = item.owner.role, owner != me {
            parts.append("waiting for \(room.name(of: owner))")
        }
        if !item.isDecided, let s = item.suggestion, let by = item.suggestedBy, by != me {
            parts.append("\(room.name(of: by)) suggests \(s.shortLabel.lowercased())")
        }
        if let owner = SortRules.ownerLabel(item, room: room, me: me), item.isDecided || item.owner == .shared {
            parts.append(owner)
        }
        return parts.joined(separator: ", ")
    }

    @ScaledMetric(relativeTo: .footnote) private var tagHeight: CGFloat = Size.tag

    @ViewBuilder private var subline: some View {
        let asked = SortRules.isAskedOf(item, me: me)
        if item.isDecided {
            // The decision as its gradient tag: icon and word, so it never relies on colour.
            StatusTag(item: item, room: room, me: me)
            if let by = decidedByOther {
                Text("by \(by)").textRole(.secondary)
            }
        } else if asked, let by = item.askBy {
            AppTag(kind: .suggestion, text: "\(room.name(of: by)) asked you")
        } else if item.askBy == me, let to = item.askTo {
            Text("Asked \(room.name(of: to))").textRole(.secondary)
        } else if let owner = item.owner.role, owner != me {
            Label("Waiting for \(room.name(of: owner))", systemImage: ItemStatus.undecided.icon).textRole(.secondary)
        } else {
            Label("Undecided", systemImage: ItemStatus.undecided.icon).textRole(.secondary)
        }
        if !item.isDecided, let s = item.suggestion, let by = item.suggestedBy, by != me {
            AppTag(kind: .suggestion, text: "\(room.name(of: by)): \(s.shortLabel.lowercased())")
        }
        if let owner = SortRules.ownerLabel(item, room: room, me: me), item.isDecided || item.owner == .shared {
            AppTag(kind: .neutral, text: owner)
        }
    }

    /// "you" or "Alex": who decided. Always shown once two people share the room; on your own,
    /// only when it wasn't the owner who decided.
    private var decidedByOther: String? {
        guard let by = item.decidedBy else { return nil }
        let notOwner = item.owner != .shared && item.owner != .unassigned && by != item.owner.role
        guard room.guestHasJoined || notOwner else { return nil }
        return by == me ? "you" : room.name(of: by)
    }
}

/// The five decisions (or four suggestions when it's not your call), one per row.
/// The chosen one fills with sage and gets a tick; the icon and words always say which it is.
struct DecisionButtons: View {
    let item: Item
    let room: Room
    let me: Role
    var disabled = false
    /// Called after a choice is saved (or cleared by tapping it again).
    var onChoose: ((ItemStatus) -> Void)?
    @Environment(SyncEngine.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var suggesting: Bool { !SortRules.canDecide(item, as: me, in: room) }

    var body: some View {
        FlowLayout(spacing: Space.s) {
            ForEach(suggesting ? ItemStatus.suggestions : ItemStatus.decisions, id: \.self) { status in
                let on = suggesting ? (item.suggestion == status && item.suggestedBy == me) : item.status == status
                DecisionButton(decision: status, title: label(status), isSelected: on, layout: .compact, suggesting: suggesting) {
                    // A light tap, and only the button and the status tag cross-fade.
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withMotion(Motion.subtleFade, reduceMotion: reduceMotion) {
                        SortActions.choose(status, for: item, as: me, in: room, sync: sync)
                    }
                    onChoose?(status)
                }
            }
        }
        .disabled(disabled)
    }

    /// "Send" reads oddly when it's someone else's thing: "Send to Alex".
    private func label(_ status: ItemStatus) -> String {
        guard status == .sendToOwner, suggesting else { return status.shortLabel }
        let to = item.owner.role ?? me.other
        return "Send to \(room.name(of: to))"
    }
}
