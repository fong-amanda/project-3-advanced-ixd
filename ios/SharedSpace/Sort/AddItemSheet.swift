import SwiftData
import SwiftUI

/// Add something the scan missed, or build a room by hand on a phone without LiDAR.
struct AddItemSheet: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @Query private var items: [Item]
    @State private var name = ""
    @State private var category: ItemCategory = .other
    @State private var added: [String] = []

    init(room: Room) {
        self.room = room
        _items = Query(Item.live(in: room.id))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What is it?") {
                    TextField("For example, sewing machine", text: $name)
                        .onChange(of: name) { _, new in
                            let guess = ItemCategory.guess(from: new)
                            if guess != .other { category = guess }
                        }
                        .onSubmit(add)
                }
                Section("Closest type") {
                    FlowLayout(spacing: 6) {
                        ForEach(ItemCategory.addable) { kind in
                            Chip(title: kind.label, isOn: category == kind) { category = kind }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !added.isEmpty {
                    Section("Added") {
                        ForEach(added, id: \.self) { Label($0, systemImage: "checkmark") }
                    }
                }
            }
            .navigationTitle("Add something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(added.isEmpty ? "Cancel" : "Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add).disabled(name.trimmed.isEmpty && category == .other)
                }
            }
        }
    }

    /// Adds and clears the form so several things can be entered in a row.
    private func add() {
        let label = name.trimmed.isEmpty ? category.label : name.trimmed
        SortActions.addItem(name: label, category: category, to: room, existing: items, sync: sync)
        added.append(label)
        name = ""
        category = .other
    }
}
