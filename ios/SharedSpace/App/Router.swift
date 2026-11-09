import Observation
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case home, sort, redesign, people
}

/// Screens pushed on the Home tab.
enum HomeRoute: Hashable {
    case room(UUID)
}

/// Screens pushed inside the Redesign tab.
enum RoomRoute: Hashable {
    case design(UUID)
}

struct JoinRequest: Identifiable {
    var code: String
    var id: String { code }
}

/// App-level navigation: the selected tab, the Home stack, and the current room
/// (the one Sort, Redesign and People work on).
@MainActor
@Observable
final class Router {
    private static let lastRoomKey = "ss.lastRoomId"

    var tab: AppTab = .home
    var homePath: [HomeRoute] = []
    /// Remembered between launches. nil (or a deleted room) falls back to the newest room.
    var currentRoomId: UUID? {
        didSet { UserDefaults.standard.set(currentRoomId?.uuidString, forKey: Self.lastRoomKey) }
    }
    var showNewRoom = false
    /// Set by "I’m invited" or an invite link; shows the join sheet.
    var joinRequest: JoinRequest?

    init() {
        currentRoomId = UserDefaults.standard.string(forKey: Self.lastRoomKey).flatMap(UUID.init(uuidString:))
    }

    /// Opens a room from Home (or after creating/joining one): pushes its overview on the Home tab.
    func openRoom(_ id: UUID, showing tab: AppTab = .home) {
        currentRoomId = id
        homePath = [.room(id)]
        self.tab = tab
    }

    /// Makes a room current without leaving the tab you're on (the title menu's room switcher).
    func switchRoom(to id: UUID) {
        currentRoomId = id
        if !homePath.isEmpty { homePath = [.room(id)] }
    }

    /// After deleting or leaving the current room.
    func closeRoom() {
        currentRoomId = nil
        homePath = []
        tab = .home
    }
}

/// The tab bar is always there. Home lists rooms; Sort, Redesign and People work on the current room.
struct RootView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(Router.self) private var router
    @State private var session = RoomSession()
    @Query(filter: #Predicate<Room> { $0.deletedAt == nil }, sort: \Room.createdAt, order: .reverse)
    private var rooms: [Room]
    @Query(filter: #Predicate<Item> { $0.deletedAt == nil }) private var allItems: [Item]

    private var currentRoom: Room? {
        rooms.first { $0.id == router.currentRoomId } ?? rooms.first
    }

    /// Undecided items the current person is responsible for, in the current room. Live.
    private var undecidedCount: Int {
        guard let room = currentRoom else { return 0 }
        let items = allItems.filter { $0.roomId == room.id }
        let mine = session.me(in: room, userId: sync.userId) == .guest ? SortRules.items(items, belongingTo: .guest) : items
        return mine.filter { !$0.isDecided }.count
    }

    private var sortTitle: String {
        guard let room = currentRoom else { return "Sort" }
        return session.me(in: room, userId: sync.userId) == .guest ? "Your things" : "Sort"
    }

    var body: some View {
        @Bindable var router = router
        @Bindable var sync = sync
        @Bindable var session = session
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView()
                        .navigationDestination(for: HomeRoute.self) { route in
                            switch route {
                            case .room(let id): RoomOverviewScreen(roomId: id)
                            }
                        }
                }
            }
            Tab(sortTitle, systemImage: "checklist", value: AppTab.sort) {
                NavigationStack {
                    if let room = currentRoom { SortView(room: room).id(room.id) } else { NoRoomChosenView(tool: "Sort") }
                }
            }
            .badge(undecidedCount)
            Tab("Redesign", systemImage: "cube", value: AppTab.redesign) {
                NavigationStack(path: $session.redesignPath) {
                    Group {
                        if let room = currentRoom { RedesignHomeView(room: room).id(room.id) } else { NoRoomChosenView(tool: "Redesign") }
                    }
                    .navigationDestination(for: RoomRoute.self) { route in
                        switch route {
                        case .design(let id): DesignEditorView(roomId: currentRoom?.id ?? id, designId: id)
                        }
                    }
                }
            }
            Tab("People", systemImage: "person.2", value: AppTab.people) {
                NavigationStack {
                    if let room = currentRoom { PeopleView(room: room).id(room.id) } else { NoRoomChosenView(tool: "People") }
                }
            }
        }
        .task(id: currentRoom?.id) {
            session.reset(for: currentRoom?.id)
            #if DEBUG
            if DemoData.asGuest { session.previewAsGuest = true }
            #endif
            if let id = currentRoom?.id { await sync.openRoom(id) } else { await sync.closeRoom() }
        }
        .sheet(isPresented: $router.showNewRoom) {
            NewRoomSheet { room in router.openRoom(room.id) }
        }
        .sheet(item: $router.joinRequest) { request in
            JoinRoomSheet(initialCode: request.code) { roomId in
                // Guests land on their own things, ready to review one at a time.
                let isGuest = rooms.first { $0.id == roomId }?.role(of: sync.userId) == .guest
                router.openRoom(roomId, showing: isGuest ? .sort : .home)
            }
        }
        .sheet(isPresented: $session.showAddItem) { if let room = currentRoom { AddItemSheet(room: room) } }
        .sheet(isPresented: $session.showSettings) { if let room = currentRoom { RoomSettingsSheet(room: room) } }
        .fullScreenCover(isPresented: $session.showScan) { if let room = currentRoom { ScanFlowView(room: room) } }
        .alert("This iPhone can’t scan rooms", isPresented: $session.showScanUnsupported) {
            Button("Add items by hand") { session.showAddItem = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Scanning needs an iPhone with LiDAR, such as an iPhone Pro. You can still add things by hand, sort them, and redesign the room.")
        }
        .activityBanner($sync.activity)
        .environment(session)
    }
}

/// Pushed from Home. Makes the room current so the other tabs follow it.
private struct RoomOverviewScreen: View {
    let roomId: UUID
    @Environment(Router.self) private var router
    @Query private var rooms: [Room]

    init(roomId: UUID) {
        self.roomId = roomId
        _rooms = Query(filter: #Predicate<Room> { $0.id == roomId && $0.deletedAt == nil })
    }

    var body: some View {
        Group {
            if let room = rooms.first {
                RoomOverviewView(room: room)
            } else {
                ContentUnavailableView("This room no longer exists", systemImage: "door.left.hand.closed",
                                       description: Text("It may have been deleted by the person who made it."))
            }
        }
        .onAppear { if router.currentRoomId != roomId { router.currentRoomId = roomId } }
    }
}

/// Sort / Redesign / People before any room has been opened.
private struct NoRoomChosenView: View {
    let tool: String
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<Room> { $0.deletedAt == nil }) private var rooms: [Room]

    var body: some View {
        ContentUnavailableView {
            Label(rooms.isEmpty ? "No rooms yet" : "Choose a room", systemImage: "square.dashed")
        } description: {
            Text(rooms.isEmpty ? "\(tool) works on a room. Add the room you want to change, or join one you were invited to."
                               : "Open a room from Home and \(tool) will show it here.")
        } actions: {
            if rooms.isEmpty {
                Button { router.showNewRoom = true } label: { Label("New room", systemImage: "plus") }
                    .buttonStyle(.pill(.primary, fullWidth: false))
            }
            Button("Go to Home") { router.tab = .home }
                .buttonStyle(.pill(.secondary, fullWidth: false))
        }
        .background(Color.ssBg)
        .navigationTitle(tool)
        .navigationBarTitleDisplayMode(.inline)
    }
}
