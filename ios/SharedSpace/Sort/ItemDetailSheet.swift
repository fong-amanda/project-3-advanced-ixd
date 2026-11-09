import SwiftUI

/// Everything about one item: name and type, whose it is, the decision (or a suggestion),
/// where it's moving, when it's picked up, and a note.
struct ItemDetailSheet: View {
    let item: Item
    let room: Room
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @Environment(RoomSession.self) private var session

    @State private var name = ""
    @State private var note = ""
    @State private var destination = ""
    @State private var showAddGuest = false
    @State private var confirmRemove = false

    private var context: RoomContext { session.context(room, userId: sync.userId) }
    private var me: Role { context.me }
    private var canDecide: Bool { SortRules.canDecide(item, as: me, in: room) }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                ownerSection
                if item.owner != .unassigned { decisionSection }
                if item.status == .keepMove && canDecide { moveSection }
                if item.status == .sendToOwner { pickupSection }
                noteSection
                if context.canEditRoom {
                    Section {
                        Button("Remove from this room’s list", role: .destructive) { confirmRemove = true }
                    } footer: {
                        Text("Use this for things that aren’t really here. To get rid of something, choose Let go.")
                    }
                }
            }
            .disabled(context.readOnly)
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { commitText(); dismiss() } }
            }
            .onAppear {
                name = item.name
                note = item.note
                destination = item.moveDestination ?? ""
            }
            .onDisappear(perform: commitText)
            .sheet(isPresented: $showAddGuest) {
                AddGuestSheet(room: room) { SortActions.setOwner(.guest, for: item, sync: sync) }
            }
            .confirmationDialog("Remove \(item.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    SortActions.remove(item, sync: sync)
                    dismiss()
                }
            }
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                ItemThumb(item: item, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    if context.canEditRoom {
                        TextField("Name", text: $name)
                            .font(.title3.weight(.semibold))
                            .onSubmit(commitText)
                    } else {
                        Text(item.name).font(.title3.weight(.semibold))
                    }
                    Text("About \(Int(item.widthCm)) × \(Int(item.depthCm)) × \(Int(item.heightCm)) cm")
                        .font(.caption).foregroundStyle(Color.ssMuted)
                }
            }
            if context.canEditRoom {
                Picker("Type", selection: Binding(get: { item.category }, set: { item.category = $0; sync.save(item) })) {
                    ForEach(ItemCategory.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }

    private var ownerSection: some View {
        Section {
            Picker("Whose is it?", selection: Binding(get: { item.owner }, set: pickOwner)) {
                Text(me == .host ? "Mine" : room.name(of: .host)).tag(Owner.host)
                Text(me == .guest ? "Mine" : (room.hasGuest ? room.name(of: .guest) : "Someone else’s")).tag(Owner.guest)
                Text("Shared").tag(Owner.shared)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Whose is it?")
        } footer: {
            if item.owner == .unassigned {
                Text("Say whose it is first. Then the owner decides what happens to it.")
            } else if item.owner != .shared {
                Text("Changing the owner clears the decision, so the new owner can decide.")
            }
        }
    }

    private var decisionSection: some View {
        Section {
            if let s = item.suggestion, let by = item.suggestedBy, by != me {
                HStack {
                    Label("\(room.name(of: by)) suggests: \(s.buttonLabel.lowercased())", systemImage: "text.bubble")
                        .foregroundStyle(Color.ssAccentInk)
                    Spacer()
                    if canDecide {
                        Button("Use it") { SortActions.choose(s, for: item, as: me, in: room, sync: sync) }
                            .buttonStyle(.bordered)
                    }
                }
                .listRowBackground(Color.ssAccentSoft)
            }
            if !canDecide, item.isDecided, let by = item.decidedBy {
                StatusTag(item: item, room: room, me: me)
                Text("\(room.name(of: by)) decided this. It’s their call, but you can suggest something else.")
                    .font(.footnote).foregroundStyle(Color.ssMuted)
            }
            DecisionButtons(item: item, room: room, me: me)
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        } header: {
            Text(canDecide ? "What happens to it?" : "\(ownerName) decides. You can suggest:")
        } footer: {
            if SortRules.isDecidingForGuest(item, as: me, in: room) {
                Text("\(room.name(of: .guest)) hasn’t joined yet, so you can decide for them.")
            } else if item.isDecided && canDecide {
                Text(SortRules.statusText(item, room: room, me: me) + ". Tap it again to undo.")
            }
        }
    }

    private var moveSection: some View {
        Section("Where in the house?") {
            TextField("For example, hall closet", text: $destination)
                .onSubmit(commitText)
        }
    }

    @ViewBuilder private var pickupSection: some View {
        let canSet = SortActions.canSetPickup(item, as: me, in: room)
        Section {
            if canSet {
                Toggle("Set a pickup date", isOn: Binding(
                    get: { item.pickupDate != nil },
                    set: { SortActions.setPickupDate($0 ? Calendar.current.date(byAdding: .day, value: 7, to: .now) : nil,
                                                     for: item, sync: sync) }))
                if let date = item.pickupDate {
                    DatePicker("Pickup", selection: Binding(get: { date }, set: { SortActions.setPickupDate($0, for: item, sync: sync) }),
                               in: Date.now..., displayedComponents: .date)
                }
            } else if let date = item.pickupDate {
                LabeledContent("Pickup", value: date.formatted(date: .complete, time: .omitted))
            } else {
                Text("\(room.name(of: SortRules.recipient(of: item))) hasn’t picked a date yet.")
                    .foregroundStyle(Color.ssMuted)
            }
        } header: {
            Text("Pickup")
        }
    }

    private var noteSection: some View {
        Section {
            TextField("For example: the left drawer sticks", text: $note, axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text("Note")
        } footer: {
            if let by = item.noteBy, !item.note.isEmpty {
                Text("From \(by == me ? "you" : room.name(of: by)).")
            }
        }
    }

    // MARK: Helpers

    private var ownerName: String {
        room.name(of: item.owner == .host ? .host : .guest)
    }

    private func pickOwner(_ owner: Owner) {
        if owner == .guest && !room.hasGuest {
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
        if item.status == .keepMove, destination.trimmed != (item.moveDestination ?? "") {
            SortActions.setMoveDestination(destination, for: item, sync: sync)
        }
    }
}
