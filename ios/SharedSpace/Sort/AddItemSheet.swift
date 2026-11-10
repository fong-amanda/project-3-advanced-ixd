import SwiftData
import SwiftUI

/// Add something to the room, optionally at the spot tapped on a room photo.
struct AddItemSheet: View {
    let room: Room
    var pin: CGPoint?
    var photo = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @Query private var items: [Item]
    @State private var name = ""
    @State private var category: ItemCategory = .other
    @State private var showMore = false

    static let common: [ItemCategory] = [.desk, .chair, .bed, .bookshelf, .boxes, .rug]

    init(room: Room, pin: CGPoint? = nil, photo: Int = 0) {
        self.room = room
        self.pin = pin
        self.photo = photo
        _items = Query(Item.live(in: room.id))
    }

    /// On a second or third photo, things already listed can be marked instead of added again.
    private var unmarked: [Item] {
        guard pin != nil, photo > 0 else { return [] }
        return items.filter { $0.pin(on: photo) == nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if !unmarked.isEmpty {
                        VStack(alignment: .leading, spacing: Space.s) {
                            SectionLabel("Already listed? Mark it here")
                            FlowLayout(spacing: Space.s) {
                                ForEach(unmarked) { item in
                                    AppChip(title: item.name, isSelected: false) {
                                        if let pin { SortActions.setPin(pin, photo: photo, for: item, sync: sync) }
                                        dismiss()
                                    }
                                }
                            }
                            Text("Each thing has one number, so this moves its number to this photo.")
                                .textRole(.hint)
                        }
                        SectionLabel("Or add something new")
                    }
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("What is it?")
                        TextField("Sewing machine", text: $name)
                            .textFieldStyle(.app)
                            .submitLabel(.done)
                            .onSubmit(add)
                            .onChange(of: name) { _, new in
                                let guess = ItemCategory.guess(from: new)
                                if guess != .other { category = guess }
                            }
                    }
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Type")
                        FlowLayout(spacing: Space.s) {
                            ForEach(Self.common) { kind in chip(kind) }
                        }
                        DisclosureGroup("More item types", isExpanded: $showMore) {
                            FlowLayout(spacing: Space.s) {
                                ForEach(ItemCategory.addable.filter { !Self.common.contains($0) }) { kind in chip(kind) }
                            }
                            .padding(.top, Space.m)
                        }
                        .font(.detailStrong)
                        .tint(Color.iconNeutral)
                        .frame(minHeight: Size.tapTarget)
                    }
                    Button("Add to the room", action: add)
                        .buttonStyle(.app)
                        .disabled(name.trimmed.isEmpty && category == .other)
                }
                .padding(Space.page)
            }
            .appSheet()
            .appNavigation("Add something")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { if !Self.common.contains(category) && category != .other { showMore = true } }
        }
        .presentationDetents([.large])
    }

    private func chip(_ kind: ItemCategory) -> some View {
        AppChip(title: kind.label, isSelected: category == kind) {
            category = kind
            if name.trimmed.isEmpty, kind != .other { name = kind.label }
        }
    }

    private func add() {
        let label = name.trimmed.isEmpty ? category.label : name.trimmed
        guard !label.isEmpty else { return }
        SortActions.addItem(name: label, category: category, owner: SortActions.defaultOwner(in: room, items: items),
                            pin: pin ?? (RoomPhotos.available(room, revision: sync.photoRevision).isEmpty ? nil : CGPoint(x: 0.5, y: 0.5)),
                            photo: pin == nil ? 0 : photo, to: room, existing: items, sync: sync)
        dismiss()
    }
}
