import SwiftUI

/// Shown when the last undecided thing gets a decision. The host can go on to the room plan.
struct SortSummarySheet: View {
    let items: [Item]
    let room: Room
    let me: Role
    var onSeeRoom: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var progress: SortProgress { SortProgress(items) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    VStack(spacing: Space.xs) {
                        ForEach(ItemStatus.decisions + [.keepMove], id: \.self) { status in
                            let count = progress.byStatus[status] ?? 0
                            if count > 0 {
                                HStack(spacing: Space.m) {
                                    Image(systemName: status.icon).foregroundStyle(status.color).frame(width: Size.iconColumn)
                                        .accessibilityHidden(true)
                                    Text(status.statusLabel)
                                    Spacer()
                                    Text("\(count)").font(.bodyStrong)
                                }
                                .padding(.vertical, Space.m)
                                .accessibilityElement(children: .combine)
                                Hairline()
                            }
                        }
                    }
                    if progress.freedCm2 > 500 {
                        Text("\(room.unitSystem.area(progress.freedCm2)) of floor freed up.")
                            .textRole(.secondary)
                    }
                    Text("You can change any decision at any time.").textRole(.hint)
                    if me == .host {
                        Button("See the room") {
                            dismiss()
                            onSeeRoom()
                        }
                        .buttonStyle(.app)
                    }
                }
                .padding(Space.page)
            }
            .appSheet()
            .appNavigation(me == .guest ? "All done, thank you" : "Everything’s decided")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
