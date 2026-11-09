import Observation
import SwiftData
import SwiftUI

/// The two tabs inside a room.
enum RoomTab: Hashable {
    case items, plan
}

/// Screens pushed inside a room tab.
enum RoomRoute: Hashable {
    case people
}

struct JoinRequest: Identifiable {
    var code: String
    var id: String { code }
}

/// App-level navigation. Home lists your rooms; opening one shows that room with its own two tabs
/// (Items and Room plan). People & sharing lives in the room's ⋯ menu.
@MainActor
@Observable
final class Router {
    /// The room on screen, or nil for the room list.
    var openRoomId: UUID?
    var roomTab: RoomTab = .items
    var showNewRoom = false
    var showAddRoom = false
    /// Set by "Join with a code" or an invite link; shows the join sheet.
    var joinRequest: JoinRequest?

    func openRoom(_ id: UUID, showing tab: RoomTab = .items) {
        roomTab = tab
        openRoomId = id
    }

    /// Back to the room list (also after deleting or leaving the room).
    func closeRoom() {
        openRoomId = nil
    }
}

struct RootView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<Room> { $0.deletedAt == nil }, sort: \Room.createdAt, order: .reverse)
    private var rooms: [Room]

    private var openRoom: Room? {
        guard let id = router.openRoomId else { return nil }
        return rooms.first { $0.id == id }
    }

    var body: some View {
        @Bindable var router = router
        @Bindable var sync = sync
        ZStack {
            if let room = openRoom {
                RoomView(room: room)
                    .id(room.id)
                    .transition(.move(edge: .trailing))
            } else {
                NavigationStack { HomeView() }
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.snappy(duration: 0.3), value: openRoom?.id)
        .task(id: openRoom?.id) {
            if let id = openRoom?.id { await sync.openRoom(id) } else { await sync.closeRoom() }
        }
        .sheet(isPresented: $router.showAddRoom) { AddRoomSheet() }
        .fullScreenCover(isPresented: $router.showNewRoom) {
            NewRoomFlow { room, invite in
                if invite { pendingInvite = room.id }
                router.openRoom(room.id)
            }
        }
        .sheet(item: $router.joinRequest) { request in
            JoinRoomSheet(initialCode: request.code) { roomId in router.openRoom(roomId) }
        }
        .activityBanner($sync.activity)
        .environment(\.pendingInvite, $pendingInvite)
    }

    /// A room just created with "Invite someone": its People screen opens the invite sheet once.
    @State private var pendingInvite: UUID?
}

/// One room: Items and Room plan, each with its own navigation stack.
struct RoomView: View {
    let room: Room
    @Environment(SyncEngine.self) private var sync
    @Environment(Router.self) private var router
    @Environment(\.pendingInvite) private var pendingInvite
    @State private var session = RoomSession()
    @Query private var items: [Item]

    init(room: Room) {
        self.room = room
        _items = Query(Item.live(in: room.id))
    }

    /// Things that need the current person: theirs to decide, or a question for them. Live.
    private var openCount: Int {
        let me = session.me(in: room, userId: sync.userId)
        return items.filter { SortRules.needsMe($0, me: me, in: room) }.count
    }

    var body: some View {
        @Bindable var router = router
        @Bindable var session = session
        TabView(selection: $router.roomTab) {
            Tab("Items", systemImage: "list.bullet", value: RoomTab.items) {
                NavigationStack(path: $session.itemsPath) {
                    ItemsView(room: room)
                        .navigationDestination(for: RoomRoute.self) { route in destination(route) }
                }
            }
            .badge(openCount)
            Tab("Room plan", systemImage: "cube", value: RoomTab.plan) {
                NavigationStack(path: $session.planPath) {
                    RoomPlanView(room: room)
                        .navigationDestination(for: RoomRoute.self) { route in destination(route) }
                }
            }
        }
        .tint(.accent)
        .sheet(item: $session.addItem) { request in
            AddItemSheet(room: room, pin: request.pin, photo: request.photo)
        }
        .sheet(isPresented: $session.showSettings) { RoomSettingsSheet(room: room) }
        .fullScreenCover(isPresented: $session.showScan) {
            ScanFlowView { result, captured in
                ScanActions.apply(result, captured: captured, to: room, items: items, sync: sync)
                sync.activity = ActivityEvent(text: "Scan saved: \(result.objects.count) things found", symbol: "viewfinder", status: nil)
            }
        }
        .environment(session)
        .onAppear {
            #if DEBUG
            if DemoData.asGuest { session.previewAsGuest = true }
            #endif
            if pendingInvite.wrappedValue == room.id {
                pendingInvite.wrappedValue = nil
                session.showInviteOnPeople = true
                session.show(.people, on: router.roomTab)
            }
        }
    }

    @ViewBuilder private func destination(_ route: RoomRoute) -> some View {
        switch route {
        case .people: PeopleView(room: room)
        }
    }
}

private struct PendingInviteKey: EnvironmentKey {
    static let defaultValue: Binding<UUID?> = .constant(nil)
}

extension EnvironmentValues {
    var pendingInvite: Binding<UUID?> {
        get { self[PendingInviteKey.self] }
        set { self[PendingInviteKey.self] = newValue }
    }
}
