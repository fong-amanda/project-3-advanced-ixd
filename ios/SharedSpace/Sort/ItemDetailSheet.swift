import SwiftUI

/// One thing: the decision (or a suggestion), asking the other person, whose it is, a note,
/// and, under Details, renaming or removing it.
struct ItemDetailSheet: View {
    let item: Item
    let room: Room
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @Environment(RoomSession.self) private var session

    @State private var name = ""
    @State private var note = ""
    @State private var showAddGuest = false
    @State private var confirmRemove = false
    @State private var showDetails = false

    private var context: RoomContext { session.context(room, userId: sync.userId) }
    private var me: Role { context.me }
    private var canDecide: Bool { SortRules.canDecide(item, as: me, in: room) }
    private var units: UnitSystem { room.unitSystem }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header
                    decision
                    if room.hasGuest && !SortRules.isAskedOf(item, me: me) && !item.isDecided { askButton }
                    if room.hasGuest || me == .guest { ownerPicker }
                    noteField
                    details
                }
                .padding(Space.page)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(context.readOnly)
            .appSheet()
            .appNavigation(item.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { commitText(); dismiss() } }
            }
            .onAppear {
                name = item.name
                note = item.note
            }
            .onDisappear(perform: commitText)
            .sheet(isPresented: $showAddGuest) {
                AddGuestSheet(room: room, items: room.liveItems) { SortActions.setOwner(.guest, for: item, sync: sync) }
            }
            .confirmationDialog("Remove \(item.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    SortActions.remove(item, sync: sync)
                    dismiss()
                }
            } message: {
                Text("Use this for things that aren’t really here. To get rid of something, choose Donate or sell, or Throw out.")
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: Space.l) {
            ItemThumb(item: item, size: 72)
            VStack(alignment: .leading, spacing: Space.s) {
                Text(item.name).textRole(.sectionTitle)
                Text(units.dims(item.widthCm, item.depthCm, item.heightCm)).textRole(.secondary)
                if item.isDecided {
                    StatusTag(item: item, room: room, me: me)
                } else if let owner = item.owner.role, owner != me {
                    AppTag(kind: .neutral, text: "Waiting for \(room.name(of: owner))")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var decision: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let s = item.suggestion, let by = item.suggestedBy, by != me, !item.isDecided {
                NoteBar(text: "\(room.name(of: by)) suggests: \(s.shortLabel.lowercased())") {
                    if canDecide {
                        Button("Use it") { SortActions.choose(s, for: item, as: me, in: room, sync: sync) }
                            .frame(minHeight: Size.tapTarget)
                    }
                }
            }
            if SortRules.isAskedOf(item, me: me), let by = item.askBy {
                NoteBar(text: "\(room.name(of: by)) asked what you think should happen to this.")
            }
            SectionLabel(canDecide ? "Your decision" : "Suggest what to do")
            if !canDecide, item.isDecided {
                Text("\(room.name(of: item.decidedBy ?? item.owner.role ?? .host)) chose \(SortRules.statusText(item, room: room, me: me).lowercased()).")
                    .textRole(.secondary)
            }
            DecisionButtons(item: item, room: room, me: me)
            if item.isDecided && canDecide {
                Text("Tap it again to undo.").textRole(.hint)
            }
        }
    }

    private var askButton: some View {
        let asked = item.askBy == me
        return Button {
            SortActions.ask(about: item, as: me, sync: sync)
            sync.activity = ActivityEvent(text: "Asked \(room.name(of: me.other))", symbol: "text.bubble", status: nil)
            dismiss()
        } label: {
            Label(asked ? "Asked \(room.name(of: me.other))" : "Ask \(room.name(of: me.other)) what to do", systemImage: "text.bubble")
        }
        .buttonStyle(.app(.primary, selected: asked))
        .disabled(asked)
    }

    private var ownerPicker: some View {
        let other = me.other
        let segments: [ChipOption<Owner>] = [
            .init(value: Owner(me), title: "Me"),
            .init(value: Owner(other), title: room.hasGuest || other == .host ? room.name(of: other) : "Someone else"),
            .init(value: .shared, title: "Both"),
        ]
        return VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel("Belongs to")
            ChipPicker(options: segments, selection: Binding(get: { item.owner == .unassigned ? .host : item.owner }, set: pickOwner))
            if item.isDecided && item.owner != .shared {
                Text("Changing the owner clears the decision, so the new owner can decide.")
                    .textRole(.hint)
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel("Note")
            TextField("Anything the other person should know", text: $note, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.appArea)
                .accessibilityLabel("Note")
            if let by = item.noteBy, !item.note.isEmpty {
                Text("From \(by == me ? "you" : room.name(of: by)).").textRole(.hint)
            }
        }
    }

    @ViewBuilder private var details: some View {
        if context.canEditRoom {
            DisclosureGroup("Details", isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: Space.m) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Name")
                        TextField("Name", text: $name).textFieldStyle(.app).onSubmit(commitText)
                    }
                    Picker("Type", selection: Binding(get: { item.category }, set: { item.category = $0; sync.save(item) })) {
                        ForEach(ItemCategory.allCases) { Text($0.label).tag($0) }
                    }
                    .frame(minHeight: Size.tapTarget)
                    Button("Remove from the list", role: .destructive) { confirmRemove = true }
                        .buttonStyle(.app(.destructive, size: .compact))
                }
                .padding(.top, Space.m)
            }
            .font(.detailStrong)
            .tint(Color.iconNeutral)
        }
    }

    // MARK: Helpers

    private func pickOwner(_ owner: Owner) {
        if owner == .guest && !room.hasGuest && context.realRole == .host {
            showAddGuest = true
        } else {
            SortActions.setOwner(owner, for: item, sync: sync)
        }
    }

    private func commitText() {
        guard !context.readOnly, item.deletedAt == nil else { return }
        if context.canEditRoom, !name.trimmed.isEmpty, name.trimmed != item.name {
            item.name = name.trimmed
            sync.save(item)
        }
        SortActions.setNote(note, for: item, as: me, sync: sync)
    }
}
