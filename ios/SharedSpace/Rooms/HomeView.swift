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
                    LazyVStack(spacing: Space.xl) {
                        ForEach(rooms) { room in
                            Button { router.openRoom(room.id) } label: {
                                RoomSummaryCard(room: room, me: room.role(of: sync.userId))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
        }
        .background(Color.pageBackground)
        .navigationTitle("Rooms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BrandMark().frame(width: Size.brandMark, height: Size.brandMark)
                    #if DEBUG
                    .onLongPressGesture { showDesignSystem = true }
                    #endif
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.showAddRoom = true } label: {
                    Image(systemName: "plus").frame(minWidth: Size.tapTarget, minHeight: Size.tapTarget)
                }
                .accessibilityLabel("Add a room")
            }
        }
        .refreshable { await sync.refresh() }
        #if DEBUG
        .sheet(isPresented: $showDesignSystem) { DesignSystemGallery() }
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-designSystem") { showDesignSystem = true } }
        #endif
    }

    @State private var showDesignSystem = false

    private var emptyState: some View {
        VStack(spacing: Space.l) {
            Text("No rooms yet").font(.cardTitle)
            Button { router.showNewRoom = true } label: { Label("Add a room", systemImage: "plus") }
                .buttonStyle(.app(.primary, width: .hug))
            Button("Join with a code") { router.joinRequest = JoinRequest(code: "") }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.xxxl)
        .overlay(RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Color.outlineStrong, style: StrokeStyle(lineWidth: Stroke.bold, dash: Stroke.dashed)))
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
            .navigationTitle("Add a room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func row(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.l) {
                Image(systemName: symbol).foregroundStyle(Color.accentText).frame(width: Size.iconColumn)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title).textRole(.bodyStrong)
                    Text(detail).textRole(.secondary)
                }
                Spacer()
                RowChevron()
            }
            .padding(.vertical, Space.s)
        }
    }
}

struct LocalOnlyNotice: View {
    var body: some View {
        Label {
            Text("Sharing is off in this build, so rooms stay on this iPhone. Add your Supabase keys to Supabase.plist to sort together.")
                .font(.footnoteText)
        } icon: {
            Image(systemName: "icloud.slash")
        }
        .foregroundStyle(Color.textSecondary)
        .card(padding: Space.m)
    }
}
