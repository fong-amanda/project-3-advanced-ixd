import SwiftUI

// Placeholder until stage 2 (RoomPlan scanning).
struct ScanFlowView: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Scanning arrives in stage 2", systemImage: "viewfinder")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
