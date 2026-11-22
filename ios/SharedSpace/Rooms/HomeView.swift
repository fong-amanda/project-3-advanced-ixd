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
                if active.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: Space.l) {
                        ForEach(Array(active.enumerated()), id: \.element.id) { i, room in
                            card(room, tint: Theme.roomTints[i % Theme.roomTints.count])
                        }
                    }
                }
                if !archived.isEmpty { archivedSection }
            }
            .pagePadding()
            .padding(.bottom, Size.floatingClearance)
        }
        .pageBackground()
        .roomRemoval(deleting: $deleting, leaving: $leaving)
        .undoBanner(Bindable(router).archiveUndo, text: "Room archived") { undo in
            guard let room = rooms.first(where: { $0.id == undo.roomId }) else { return }
            withMotion(reduceMotion: reduceMotion) { sync.setArchived(room, false) }
        }
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
        .fullScreenCover(isPresented: $showDesignSystem) { DesignSystemGallery() }
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-designSystem") { showDesignSystem = true } }
        #endif
    }

    @State private var showDesignSystem = false
    @State private var showArchived = false
    @State private var deleting: Room?
    @State private var leaving: Room?
    @State private var cardWidth: CGFloat = 350
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Archiving is per person: these are the rooms *you* archived.
    private var active: [Room] { rooms.filter { !$0.archived } }
    private var archived: [Room] { rooms.filter(\.archived) }

    /// A room card. Tap to open; touch and hold (or ⋯) for Archive and Delete.
    private func card(_ room: Room, tint: Tone) -> some View {
        Button { router.openRoom(room.id) } label: {
            RoomSummaryCard(room: room, me: room.role(of: sync.userId), tint: tint, reservesMenuCorner: true)
        }
        .buttonStyle(PressableStyle())
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { cardWidth = $0 }
        .contextMenu {
            menu(room)
        } preview: {
            RoomSummaryCard(room: room, me: room.role(of: sync.userId), tint: tint)
                .frame(width: cardWidth)
                .environment(sync)
        }
        .overlay(alignment: .topTrailing) { moreButton(room) }
    }

    /// "⋯" in the card's corner: the same menu as touch and hold, for people who don't know about it.
    private func moreButton(_ room: Room) -> some View {
        Menu { menu(room) } label: {
            Image(systemName: "ellipsis")
                .font(.bodyStrong)
                .dynamicTypeSize(...Size.iconTypeLimit)
                .foregroundStyle(Color.textPrimary)
                .frame(width: Size.tapTarget - Space.l, height: Size.tapTarget - Space.l)
                .background(.regularMaterial, in: Circle())
                .frame(width: Size.tapTarget, height: Size.tapTarget)
                .contentShape(Rectangle())
        }
        // Sits inside the photo tile's corner (card padding + a small inset, less the extra hit area).
        .padding(.top, Space.xl + Space.xs - Space.s)
        .padding(.trailing, Space.xl + Space.xs - Space.s)
        .accessibilityLabel("Options for \(room.name)")
    }

    /// Short labels; the explanation is in the confirmation (Delete) or the undo banner (Archive).
    @ViewBuilder private func menu(_ room: Room) -> some View {
        if room.archived {
            Button("Unarchive", systemImage: "tray.and.arrow.up") { sync.setArchived(room, false) }
        } else {
            Button("Archive", systemImage: "archivebox") { archive(room) }
        }
        if room.role(of: sync.userId) == .host {
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = room }
        } else {
            Button("Leave Room", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { leaving = room }
        }
    }

    private func archive(_ room: Room) {
        withMotion(reduceMotion: reduceMotion) { sync.setArchived(room, true) }
        router.archiveUndo = .init(roomId: room.id)
    }

    /// "Archived (2)", collapsed until tapped.
    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Button { showArchived.toggle() } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "archivebox").accessibilityHidden(true)
                    Text("Archived (\(archived.count))").textRole(.bodyStrong)
                    Spacer()
                    Image(systemName: showArchived ? "chevron.up" : "chevron.down").accessibilityHidden(true)
                }
                .foregroundStyle(Color.iconNeutral)
                .frame(minHeight: Size.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showArchived ? "Expanded" : "Collapsed")
            .accessibilityHint("Rooms you archived. Only you see them as archived.")
            if showArchived {
                Text("Only hidden for you. Everything in them is kept. To unarchive a room, tap its ⋯ button or touch and hold it.")
                    .textRole(.hint)
                LazyVStack(spacing: Space.l) {
                    ForEach(archived) { room in card(room, tint: .brown) }
                }
            }
        }
        .padding(.top, Space.l)
    }

    private var emptyState: some View {
        VStack(spacing: Space.l) {
            IconCircle(symbol: "house")
            Text("No rooms yet").textRole(.cardTitle)
            Button { router.showNewRoom = true } label: { Label("Add a room", systemImage: "plus") }
                .buttonStyle(.app(.primary, width: .hug))
            Button("I’m invited") { router.joinRequest = JoinRequest(code: "") }
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
                row("Create a room", detail: "Sort what’s inside, plan a new layout, or both", symbol: "plus") {
                    dismiss()
                    router.showNewRoom = true
                }
                row("I’m invited", detail: "Join a room with the code someone sent you", symbol: "person.2") {
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
