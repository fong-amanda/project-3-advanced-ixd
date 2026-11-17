import SwiftUI

/// The two goal cards, Sort things and Plan the room. Either or both; never neither.
struct GoalPicker: View {
    @Binding var sort: Bool
    @Binding var plan: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            card(.sort, isOn: $sort)
            card(.plan, isOn: $plan)
        }
    }

    private func card(_ goal: RoomGoal, isOn: Binding<Bool>) -> some View {
        PickRow(title: goal.title, subtitle: goal.detail, isSelected: isOn.wrappedValue) {
            isOn.wrappedValue.toggle()
        }
        .accessibilityHint(isOn.wrappedValue ? "Double-tap to turn off" : "Double-tap to turn on")
    }
}

/// "Room goals…": turn sorting or planning on or off. Turning one off only hides it.
struct RoomGoalsSheet: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @Environment(Router.self) private var router
    @State private var sort = true
    @State private var plan = true

    private var none: Bool { !sort && !plan }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("What do you want to do with this room?").textRole(.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    GoalPicker(sort: $sort, plan: $plan)
                    if none {
                        NoteBar(text: "A room needs at least one goal. If you’re finished with this room, you can archive it instead. Archiving hides it, and you can bring it back anytime.",
                                symbol: "info.circle", tone: .warning)
                        Button { archive() } label: { Label("Archive this room", systemImage: "archivebox") }
                            .buttonStyle(.app(.neutral))
                    } else {
                        Text("Turning a goal off only hides it. Your items, decisions and layouts are kept, and come back when you turn it on again.")
                            .textRole(.hint)
                    }
                    Button("Save", action: save)
                        .buttonStyle(.app)
                        .disabled(none)
                }
                .padding(Space.page)
            }
            .appSheet()
            .appNavigation("Room goals")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { sort = room.sortEnabled; plan = room.planEnabled }
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard !none else { return }
        room.sortEnabled = sort
        room.planEnabled = plan
        sync.save(room)
        dismiss()
    }

    private func archive() {
        sync.setArchived(room, true)
        dismiss()
        router.closeRoom()
        router.archiveUndo = .init(roomId: room.id)
    }
}
