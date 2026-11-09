import SwiftUI

/// Shown when the last undecided item gets a decision. Ends with "Done", not a next step.
struct SortSummarySheet: View {
    let items: [Item]
    let room: Room
    let me: Role
    @Environment(\.dismiss) private var dismiss

    private var progress: SortProgress { SortProgress(items) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ItemStatus.decisions, id: \.self) { status in
                        let count = progress.byStatus[status] ?? 0
                        if count > 0 {
                            HStack {
                                Label(summaryLabel(status), systemImage: status.icon)
                                    .foregroundStyle(status.color)
                                Spacer()
                                Text("\(count)").font(.body.weight(.semibold))
                            }
                        }
                    }
                } footer: {
                    Text("You can change any decision at any time.")
                }
                if progress.freedM2 > 0.05 {
                    Section {
                        Label("\(String(format: "%.1f", progress.freedM2)) m² of floor freed up", systemImage: "sparkles")
                            .foregroundStyle(Color.ssAccentInk)
                            .listRowBackground(Color.ssAccentSoft)
                    }
                }
                let pickups = items.filter { $0.status == .sendToOwner && $0.pickupDate != nil }
                if !pickups.isEmpty {
                    Section("Pickups") {
                        ForEach(pickups) { item in
                            LabeledContent(item.name,
                                           value: item.pickupDate!.formatted(.dateTime.weekday(.abbreviated).month().day()))
                        }
                    }
                }
            }
            .navigationTitle(me == .guest ? "All done, thank you" : "Everything’s decided")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func summaryLabel(_ status: ItemStatus) -> String {
        switch status {
        case .keep: "Staying in the room"
        case .keepMove: "Moving elsewhere in the house"
        case .sendToOwner: "Going back to their owner"
        case .letGo: "Letting go"
        case .undecided: ""
        }
    }
}
