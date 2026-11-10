import SwiftUI

/// One thing in the Items list: thumbnail (with its photo number), name, and where it stands.
struct ItemRow: View {
    let item: Item
    let room: Room
    let me: Role
    var number: Int?
    /// nil = not selecting; true/false = selected or not in "Select" mode.
    var selection: Bool?

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
            }
            Spacer(minLength: 0)
            if let selection {
                TickBadge(isOn: selection)
            } else {
                RowChevron()
            }
        }
        .padding(.vertical, Space.m)
        .frame(minHeight: Size.row)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(number.map { "\($0), \(item.name)" } ?? item.name)
        .accessibilityAddTraits(selection == true ? .isSelected : [])
    }

    @ViewBuilder private var subline: some View {
        let asked = SortRules.isAskedOf(item, me: me)
        if item.isDecided {
            HStack(spacing: Space.xs) {
                Image(systemName: item.status.icon).foregroundStyle(item.status.color).accessibilityHidden(true)
                Text(decidedText)
            }
            .textRole(.secondary)
        } else if asked, let by = item.askBy {
            AppTag(kind: .suggestion, text: "\(room.name(of: by)) asked you")
        } else if item.askBy == me, let to = item.askTo {
            Text("Asked \(room.name(of: to))").textRole(.secondary)
        } else if let owner = item.owner.role, owner != me {
            Text("Waiting for \(room.name(of: owner))").textRole(.secondary)
        }
        if !item.isDecided, let s = item.suggestion, let by = item.suggestedBy, by != me {
            AppTag(kind: .suggestion, text: "\(room.name(of: by)): \(s.shortLabel.lowercased())")
        }
        if let owner = SortRules.ownerLabel(item, room: room, me: me), item.isDecided || item.owner == .shared {
            AppTag(kind: .neutral, text: owner)
        }
    }

    /// "Staying · by Alex" when someone other than the owner decided it.
    private var decidedText: String {
        var text = SortRules.statusText(item, room: room, me: me)
        if let by = item.decidedBy, item.owner != .shared, item.owner != .unassigned, by != item.owner.role {
            text += " · by \(by == me ? "you" : room.name(of: by))"
        }
        return text
    }
}

/// The five decisions (or four suggestions when it's not your call), one per row.
/// The chosen one fills with sage and gets a tick; the icon and words always say which it is.
struct DecisionButtons: View {
    let item: Item
    let room: Room
    let me: Role
    var disabled = false
    @Environment(SyncEngine.self) private var sync

    private var suggesting: Bool { !SortRules.canDecide(item, as: me, in: room) }

    var body: some View {
        FlowLayout(spacing: Space.s) {
            ForEach(suggesting ? ItemStatus.suggestions : ItemStatus.decisions, id: \.self) { status in
                let on = suggesting ? (item.suggestion == status && item.suggestedBy == me) : item.status == status
                DecisionButton(decision: status, title: label(status), isSelected: on, layout: .compact, suggesting: suggesting) {
                    SortActions.choose(status, for: item, as: me, in: room, sync: sync)
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
