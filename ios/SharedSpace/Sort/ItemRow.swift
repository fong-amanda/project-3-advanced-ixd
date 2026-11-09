import SwiftUI

/// One item in the Sort list: thumbnail, name, whose it is, and what's happening to it.
struct ItemRow: View {
    let item: Item
    let room: Room
    let me: Role

    var body: some View {
        HStack(spacing: 12) {
            ItemThumb(item: item)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name).font(.body.weight(.semibold)).lineLimit(1)
                FlowLayout(spacing: 5) {
                    ownerTag
                    if item.isDecided { StatusTag(item: item, room: room, me: me) }
                    if let s = item.suggestion, let by = item.suggestedBy, by != me {
                        Tag(text: "\(room.name(of: by)) suggests: \(s.buttonLabel.lowercased())", symbol: "text.bubble",
                            foreground: .ssAccentInk, background: .ssAccentSoft)
                    }
                    if !item.note.isEmpty { Tag(text: "Note", symbol: "text.alignleft") }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var ownerTag: some View {
        let label = SortRules.ownerLabel(item, room: room, me: me)
        switch item.owner {
        case .host: return Tag(text: label, foreground: Color(hex: "#234536"), background: .ssHostSoft)
        case .guest: return Tag(text: label, foreground: Color(hex: "#5A3D00"), background: .ssGuestSoft)
        case .shared, .unassigned: return Tag(text: label)
        }
    }
}

/// The four decision buttons (or dashed "suggest" buttons when it's not your call).
struct DecisionButtons: View {
    let item: Item
    let room: Room
    let me: Role
    var disabled = false
    @Environment(SyncEngine.self) private var sync

    private var suggesting: Bool { !SortRules.canDecide(item, as: me, in: room) }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(ItemStatus.decisions, id: \.self) { status in
                let on = suggesting ? (item.suggestion == status && item.suggestedBy == me) : item.status == status
                Button {
                    SortActions.choose(status, for: item, as: me, in: room, sync: sync)
                } label: {
                    Label(label(status), systemImage: status.icon)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(on ? (suggesting ? Color.ssAccentInk : .white) : Color.ssInk)
                        .background(on ? (suggesting ? Color.ssAccentSoft : status.color) : Color.ssSurface,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                            on ? (suggesting ? Color.ssAccent : status.color) : Color.ssLine,
                            style: StrokeStyle(lineWidth: 1.5, dash: suggesting && !on ? [5, 4] : [])))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: on)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    /// "Send to me" reads oddly when it's someone else's thing.
    private func label(_ status: ItemStatus) -> String {
        guard status == .sendToOwner else { return status.buttonLabel }
        switch item.owner {
        case .shared, .unassigned: return "Send to me"
        case .host, .guest:
            if item.owner.rawValue == me.rawValue { return "Send to me" }
            return "Send to \(room.name(of: item.owner == .host ? .host : .guest))"
        }
    }
}
