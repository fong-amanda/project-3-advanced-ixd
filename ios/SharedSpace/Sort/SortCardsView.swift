import SwiftUI

/// One thing at a time: the invited person's default, and available to the host too.
/// Your own things get a decision; things you were asked about get a suggestion.
struct SortCardsView: View {
    let room: Room
    /// What's left, in order (from SortRules.queue).
    let queue: [Item]
    /// Everything this person decides or was asked about, for "3 of 7".
    let total: Int
    let me: Role
    var readOnly = false
    @Binding var skipped: [UUID]

    @Environment(SyncEngine.self) private var sync
    @State private var noteItem: Item?

    var body: some View {
        ScrollView {
            if let item = queue.first {
                card(item)
                    .id(item.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    .padding(Space.l)
            }
        }
        .animation(.snappy, value: queue.first?.id)
        .sheet(item: $noteItem) { item in NotePrompt(item: item, me: me, other: room.name(of: me.other)) }
    }

    private func card(_ item: Item) -> some View {
        let mine = SortRules.canDecide(item, as: me, in: room)
        let done = max(0, total - queue.count)
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text(mine ? "Your belongings" : "\(room.name(of: item.askBy ?? me.other)) asked about this")
                Spacer()
                Text("\(min(done + 1, max(total, 1))) of \(max(total, 1))")
            }
            .font(.detailStrong)
            .foregroundStyle(Color.textTertiary)
            .accessibilityElement(children: .combine)

            Color.stage
                .aspectRatio(1.5, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: Size.cardImageMax)
                .overlay { cardImage(item) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))

            VStack(alignment: .leading, spacing: Space.s) {
                FlowLayout(spacing: Space.s) {
                    if item.owner == .shared {
                        AppTag(kind: .neutral, text: "Shared with \(room.name(of: me.other))")
                    } else if !mine, let owner = SortRules.ownerLabel(item, room: room, me: me) {
                        AppTag(kind: .neutral, text: owner)
                    }
                    if let s = item.suggestion, let by = item.suggestedBy, by != me {
                        AppTag(kind: .suggestion, text: "\(room.name(of: by)) suggests: \(s.shortLabel.lowercased())")
                    }
                }
                Text(item.name).font(.screenTitle).accessibilityAddTraits(.isHeader)
                if !item.note.isEmpty {
                    Text("“\(item.note)”").foregroundStyle(Color.textSecondary)
                }
            }

            VStack(spacing: Space.s) {
                ForEach(mine ? ItemStatus.decisions : ItemStatus.suggestions, id: \.self) { status in
                    choice(status, item: item, mine: mine)
                }
            }

            HStack {
                Button { noteItem = item } label: { Label("Add a note", systemImage: "text.bubble") }
                    .buttonStyle(.link)
                Spacer()
                Button("Skip for now") { withAnimation { skipped.removeAll { $0 == item.id }; skipped.append(item.id) } }
                    .buttonStyle(.link)
                    .disabled(queue.count < 2)
            }
        }
        .disabled(readOnly)
    }

    /// Larger crop of the room photo than the list thumbnails use.
    @ViewBuilder private func cardImage(_ item: Item) -> some View {
        if let x = item.pinX, let y = item.pinY,
           let crop = PhotoCrops.crop(roomId: room.id, photo: item.pinPhoto, at: CGPoint(x: x, y: y),
                                      revision: sync.photoRevision, zoom: 0.5) {
            Image(uiImage: crop).resizable().scaledToFill()
                .accessibilityLabel("Photo of the \(item.name)")
        } else {
            CategoryGlyph(category: item.category, side: Size.cardImageMax, fill: .stage)
        }
    }

    private func choice(_ status: ItemStatus, item: Item, mine: Bool) -> some View {
        DecisionButton(decision: status, title: title(status, item: item, mine: mine), detail: mine ? status.detail : nil,
                       isSelected: !mine && item.suggestion == status && item.suggestedBy == me,
                       layout: .full, suggesting: !mine) {
            withAnimation { SortActions.choose(status, for: item, as: me, in: room, sync: sync) }
            skipped.removeAll { $0 == item.id }
        }
    }

    private func title(_ status: ItemStatus, item: Item, mine: Bool) -> String {
        guard status == .sendToOwner, !mine else { return status.label }
        return "Send it to \(room.name(of: item.owner.role ?? me.other))"
    }
}

// MARK: - Note prompt

private struct NotePrompt: View {
    let item: Item
    let me: Role
    let other: String
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("\(other) will see it next to this item.").foregroundStyle(Color.textTertiary)
                TextField("For example: please keep the case too", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .padding(Space.m)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.control))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.outlineStrong))
                Button("Save note") {
                    SortActions.setNote(text, for: item, as: me, sync: sync)
                    dismiss()
                }
                .buttonStyle(.app)
                Spacer()
            }
            .padding(Space.l)
            .background(Color.surface)
            .navigationTitle("Add a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { text = item.note }
        }
        .presentationDetents([.medium])
    }
}
