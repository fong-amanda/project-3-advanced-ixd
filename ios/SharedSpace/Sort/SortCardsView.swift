import SwiftUI

/// One thing at a time: the guest's default, and available to the host too.
/// Choosing "Keep, move it" asks where; "Send to me" asks for a pickup date. Both are skippable.
struct SortCardsView: View {
    let room: Room
    /// The items this person is reviewing (already filtered to theirs for the guest).
    let items: [Item]
    let me: Role
    var readOnly = false
    var onShowList: () -> Void

    @Environment(SyncEngine.self) private var sync
    @State private var skipped: [UUID] = []
    @State private var followUp: FollowUp?
    @State private var noteItem: Item?
    @State private var detailItem: Item?

    private enum FollowUp: Identifiable {
        case destination(Item), pickup(Item)
        var id: String {
            switch self {
            case .destination(let i): "d\(i.id)"
            case .pickup(let i): "p\(i.id)"
            }
        }
    }

    /// Undecided items you can act on; ones you skipped go to the back of the line.
    private var queue: [Item] {
        let open = items.filter { !$0.isDecided }
        return open.filter { !skipped.contains($0.id) } + open.filter { skipped.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if items.isEmpty {
                    noneYours
                } else if let item = queue.first {
                    Text(header)
                        .font(.subheadline)
                        .foregroundStyle(Color.ssMuted)
                    card(item)
                        .id(item.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    allDone
                }
            }
            .padding(20)
            .animation(.snappy, value: queue.first?.id)
        }
        .sheet(item: $followUp) { followUp in
            switch followUp {
            case .destination(let item): DestinationPrompt(item: item)
            case .pickup(let item): PickupPrompt(item: item)
            }
        }
        .sheet(item: $noteItem) { item in NotePrompt(item: item, me: me) }
        .sheet(item: $detailItem) { item in ItemDetailSheet(item: item, room: room) }
    }

    private var header: String {
        let n = queue.count
        if me == .guest {
            return "\(room.name(of: .host)) is turning this room into a \(room.futureUse.lowercased().isEmpty ? "new space" : room.futureUse.lowercased()). \(n) of your things need a decision."
        }
        return "\(n) thing\(n == 1 ? "" : "s") left to decide."
    }

    // MARK: Card

    private func card(_ item: Item) -> some View {
        let canDecide = SortRules.canDecide(item, as: me, in: room)
        return VStack(alignment: .leading, spacing: 16) {
            ItemThumb(item: item, size: 120)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.ssStage, in: RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Tag(text: item.owner == .shared ? "Shared with \(room.name(of: me.other))"
                                                    : SortRules.ownerLabel(item, room: room, me: me))
                    if let s = item.suggestion, let by = item.suggestedBy, by != me {
                        Tag(text: "\(room.name(of: by)) suggests: \(s.buttonLabel.lowercased())", symbol: "text.bubble",
                            foreground: .ssAccentInk, background: .ssAccentSoft)
                    }
                }
                Text(item.name).font(.display(30))
                if !item.note.isEmpty {
                    Text("“\(item.note)”").foregroundStyle(Color.ssInk2)
                }
            }

            if item.owner == .unassigned {
                Text("Whose is it?").font(.headline)
                HStack {
                    ownerButton("Mine", owner: me == .host ? .host : .guest, item: item)
                    ownerButton(me == .host ? (room.hasGuest ? room.name(of: .guest) : "Someone else") : room.name(of: .host),
                                owner: me == .host ? .guest : .host, item: item)
                    ownerButton("Shared", owner: .shared, item: item)
                }
            } else {
                if !canDecide {
                    Text("It’s \(room.name(of: item.owner == .host ? .host : .guest))’s call. You can suggest:")
                        .font(.subheadline).foregroundStyle(Color.ssMuted)
                } else if SortRules.isDecidingForGuest(item, as: me, in: room) {
                    Text("\(room.name(of: .guest)) hasn’t joined yet, so you can decide for them.")
                        .font(.subheadline).foregroundStyle(Color.ssMuted)
                }
                VStack(spacing: 10) {
                    ForEach(ItemStatus.decisions, id: \.self) { status in
                        choice(status, item: item, suggesting: !canDecide)
                    }
                }
            }

            HStack {
                Button { noteItem = item } label: { Label("Add a note", systemImage: "text.bubble") }
                Spacer()
                Button("Decide later") { withAnimation { skipped.removeAll { $0 == item.id }; skipped.append(item.id) } }
                    .disabled(queue.count < 2)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(Color.ssSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.ssLine))
        .disabled(readOnly)
    }

    private func choice(_ status: ItemStatus, item: Item, suggesting: Bool) -> some View {
        Button {
            SortActions.choose(status, for: item, as: me, in: room, sync: sync)
            guard !suggesting else { return }
            switch status {
            case .keepMove: followUp = .destination(item)
            case .sendToOwner where SortActions.canSetPickup(item, as: me, in: room): followUp = .pickup(item)
            default: break
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)
                    .frame(width: 42, height: 42)
                    .background(status.softColor, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(status, item: item)).font(.headline).foregroundStyle(Color.ssInk)
                    Text(status.explanation).font(.subheadline).foregroundStyle(Color.ssMuted)
                }
                Spacer()
                if suggesting && item.suggestion == status && item.suggestedBy == me {
                    Image(systemName: "checkmark").foregroundStyle(Color.ssAccentInk)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 64)
            .background(Color.ssSurface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.ssLine,
                                                                       style: StrokeStyle(lineWidth: 1.5, dash: suggesting ? [5, 4] : [])))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: item.status)
    }

    private func title(_ status: ItemStatus, item: Item) -> String {
        switch status {
        case .keep: "Keep it in the room"
        case .keepMove: "Keep it, but move it"
        case .sendToOwner:
            item.owner == .shared || item.owner.rawValue == me.rawValue
                ? "Send it to me" : "Send it to \(room.name(of: item.owner == .host ? .host : .guest))"
        case .letGo: "Let it go"
        case .undecided: ""
        }
    }

    private func ownerButton(_ title: String, owner: Owner, item: Item) -> some View {
        Button(title) { SortActions.setOwner(owner, for: item, sync: sync) }
            .buttonStyle(.pill(.secondary))
    }

    // MARK: Empty and done states

    private var noneYours: some View {
        ContentUnavailableView {
            Label("Nothing of yours yet", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("\(room.name(of: .host)) hasn’t marked any of the things in here as yours. You’ll see them here as soon as they do.")
        } actions: {
            Button("See everything in the room", action: onShowList).buttonStyle(.pill(.secondary, fullWidth: false))
        }
        .padding(.top, 40)
    }

    private var allDone: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(me == .guest ? "All done, thank you" : "Nothing left to decide").font(.display(30))
            Text(me == .guest
                 ? "\(room.name(of: .host)) can see your choices now. You can change any of them at any time."
                 : "You can change any decision at any time.")
                .foregroundStyle(Color.ssInk2)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    Button { detailItem = item } label: {
                        ItemRow(item: item, room: room, me: me).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if item.id != items.last?.id { Divider() }
                }
            }
            .ssCard(padding: 12)
            Button("See everything in the room", action: onShowList).buttonStyle(.pill(.secondary))
        }
    }
}

// MARK: - Follow-up prompts

private struct DestinationPrompt: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @State private var place = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("For example, hall closet", text: $place).onSubmit(save)
                } footer: {
                    Text("Optional. It helps whoever moves it.")
                }
            }
            .navigationTitle("Where will the \(item.name.lowercased()) go?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(place.trimmed.isEmpty) }
            }
        }
        .presentationDetents([.height(260)])
    }

    private func save() {
        SortActions.setMoveDestination(place, for: item, sync: sync)
        dismiss()
    }
}

private struct PickupPrompt: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Pickup date", selection: $date, in: Date.now..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("When can you pick it up?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not sure yet") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        SortActions.setPickupDate(date, for: item, sync: sync)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct NotePrompt: View {
    let item: Item
    let me: Role
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("For example: please keep the case too", text: $text, axis: .vertical)
                    .lineLimit(3...8)
            }
            .navigationTitle("Add a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        SortActions.setNote(text, for: item, as: me, sync: sync)
                        dismiss()
                    }
                }
            }
            .onAppear { text = item.note }
        }
        .presentationDetents([.medium])
    }
}
