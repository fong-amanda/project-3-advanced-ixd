import SwiftData
import SwiftUI

/// Home: your rooms. Tap one to go into it; + adds a room or joins one with a code.
struct HomeView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<Room> { $0.deletedAt == nil }, sort: \Room.createdAt, order: .reverse)
    private var rooms: [Room]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if !sync.isShared { LocalOnlyNotice() }
                if rooms.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: Space.l) {
                        ForEach(Array(rooms.enumerated()), id: \.element.id) { i, room in
                            Button { router.openRoom(room.id) } label: {
                                RoomSummaryCard(room: room, me: room.role(of: sync.userId),
                                                tint: Theme.roomTints[i % Theme.roomTints.count])
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
            .pagePadding()
            .padding(.bottom, Size.floatingClearance)
        }
        .pageBackground()
        .appNavigation("Rooms", large: true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BrandMark().frame(width: Size.brandMark, height: Size.brandMark)
                    #if DEBUG
                    .onLongPressGesture { showDesignSystem = true }
                    #endif
            }
            .plainToolbarBackground()
        }
        .floatingAction("New room") { router.showAddRoom = true }
        .refreshable { await sync.refresh() }
        #if DEBUG
        .sheet(isPresented: $showDesignSystem) { DesignSystemGallery() }
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-designSystem") { showDesignSystem = true } }
        #endif
    }

    @State private var showDesignSystem = false

    private var emptyState: some View {
        VStack(spacing: Space.l) {
            IconCircle(symbol: "house")
            Text("No rooms yet").textRole(.cardTitle)
            Button { router.showNewRoom = true } label: { Label("Add a room", systemImage: "plus") }
                .buttonStyle(.app(.primary, width: .hug))
            Button("Join with a code") { router.joinRequest = JoinRequest(code: "") }
                .buttonStyle(.app(.neutral, size: .compact))
        }
        .frame(maxWidth: .infinity)
        .card(padding: Space.xxxl, radius: Radius.cardLarge)
    }
}

/// "Add a room": create one, or join one someone shared.
struct AddRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    var body: some View {
        NavigationStack {
            List {
                row("Create a room", detail: "Photograph it and sort what’s inside", symbol: "plus") {
                    dismiss()
                    router.showNewRoom = true
                }
                row("Join with a code", detail: "Someone shared a room with you", symbol: "person.2") {
                    dismiss()
                    router.joinRequest = JoinRequest(code: "")
                }
            }
            .scrollContentBackground(.hidden)
            .appSheet()
            .appNavigation("Add a room")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func row(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.l) {
                IconCircle(symbol: symbol)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title).textRole(.bodyStrong)
                    Text(detail).textRole(.secondary)
                }
                Spacer()
                RowChevron()
            }
            .padding(.vertical, Space.s)
            .frame(minHeight: Size.row)
        }
        .listRowBackground(Color.surfaceMuted)
    }
}

struct LocalOnlyNotice: View {
    var body: some View {
        Label {
            Text("Sharing is off in this build, so rooms stay on this iPhone. Add your Supabase keys to Supabase.plist to sort together.")
                .font(.detail)
        } icon: {
            Image(systemName: "icloud.slash")
        }
        .foregroundStyle(Color.textSecondary)
        .card(padding: Space.l)
    }
}
