import Observation
import SwiftData
import SwiftUI

/// The tabs inside a room. Room and People are always there; Sort (`items`) only while the room's
/// "Sort things" goal is on, and Redesign (`plan`) only while "Plan the room" is on.
enum RoomTab: Hashable, CaseIterable {
    case room, items, plan, people

    var title: String {
        switch self {
        case .room: "Room"
        case .items: "Sort"
        case .plan: "Redesign"
        case .people: "People"
        }
    }

    var symbol: String {
        switch self {
        case .room: "house"
        case .items: RoomGoal.sort.symbol
        case .plan: RoomGoal.plan.symbol
        case .people: "person.2"
        }
    }

    /// The tabs a room shows, in order.
    static func available(in room: Room) -> [RoomTab] {
        [.room] + (room.sortEnabled ? [.items] : []) + (room.planEnabled ? [.plan] : []) + [.people]
    }

    /// Where a room opens: its first goal.
    static func start(for room: Room) -> RoomTab {
        room.sortEnabled ? .items : (room.planEnabled ? .plan : .room)
    }
}

struct JoinRequest: Identifiable {
    var code: String
    var id: String { code }
}

/// App-level navigation. Home lists your rooms; opening one shows that room with its tabs
/// (Room, Sort, Redesign, People; Sort and Redesign follow the room's goals).
@MainActor
@Observable
final class Router {
    /// The room on screen, or nil for the room list.
    var openRoomId: UUID?
    var roomTab: RoomTab = .items
    var showNewRoom = false
    var showAddRoom = false
    /// Set by "I’m invited" or an invite link; shows the join sheet.
    var joinRequest: JoinRequest?
    /// A message that needs reading (not a passing banner), shown as an alert.
    var notice: Notice?
    /// The room just archived, while Home offers "Undo".
    var archiveUndo: ArchiveUndo?

    struct ArchiveUndo: Identifiable, Equatable {
        let id = UUID()
        let roomId: UUID
    }

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// Opens a room on `tab`, or on its first goal when `tab` is nil (or not shown in that room).
    func openRoom(_ id: UUID, showing tab: RoomTab? = nil) {
        roomTab = tab ?? .items   // RoomView moves to the room's first goal if this tab is hidden
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .transition(Motion.transition(.move(edge: .trailing), reduceMotion: reduceMotion))
            } else {
                NavigationStack { HomeView() }
                    .transition(Motion.transition(.move(edge: .leading), reduceMotion: reduceMotion))
            }
        }
        .animation(Motion.animation(Motion.screen, reduceMotion: reduceMotion), value: openRoom?.id)
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
        // No internet: say so once, plainly, until it's back. Everything keeps working on the phone.
        .safeAreaInset(edge: .top, spacing: 0) {
            if sync.isShared && !sync.isOnline {
                Label(SyncError.offline, systemImage: "wifi.slash")
                    .font(.detailStrong)
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Space.page)
                    .padding(.vertical, Space.s)
                    .background(Color.surface)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.outline).frame(height: Stroke.hairline) }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .alert(router.notice?.title ?? "", isPresented: Binding(get: { router.notice != nil }, set: { if !$0 { router.notice = nil } }),
               presenting: router.notice) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
        .alert("Couldn’t save the photo", isPresented: Binding(get: { sync.photoSaveError != nil },
                                                             set: { if !$0 { sync.photoSaveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sync.photoSaveError ?? "")
        }
        .environment(\.pendingInvite, $pendingInvite)
        // Reduce Motion: sheets, full-screen covers and pushes appear in place instead of sliding.
        // (Explicit fades from `withMotion(fade: true)` still run; implicit slides don't.)
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
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

    private var tabs: [RoomTab] { RoomTab.available(in: room) }

    var body: some View {
        @Bindable var router = router
        @Bindable var session = session
        TabView(selection: $router.roomTab) {
            Tab(RoomTab.room.title, systemImage: RoomTab.room.symbol, value: RoomTab.room) {
                NavigationStack { RoomOverviewView(room: room) }.toolbar(.hidden, for: .tabBar)
            }
            // A goal that's off hides its tab; its items, decisions and layouts stay in the room.
            if room.sortEnabled {
                Tab(RoomTab.items.title, systemImage: RoomTab.items.symbol, value: RoomTab.items) {
                    NavigationStack { ItemsView(room: room) }.toolbar(.hidden, for: .tabBar)
                }
            }
            if room.planEnabled {
                Tab(RoomTab.plan.title, systemImage: RoomTab.plan.symbol, value: RoomTab.plan) {
                    NavigationStack { RoomPlanView(room: room) }.toolbar(.hidden, for: .tabBar)
                }
            }
            Tab(RoomTab.people.title, systemImage: RoomTab.people.symbol, value: RoomTab.people) {
                NavigationStack { PeopleView(room: room) }.toolbar(.hidden, for: .tabBar)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(items: tabs.map { .init(value: $0, title: $0.title, symbol: $0.symbol, badge: $0 == .items ? openCount : 0) },
                      selection: $router.roomTab)
        }
        .onChange(of: tabs) { keepTabVisible() }
        .sheet(item: $session.addItem) { request in
            AddItemSheet(room: room, pin: request.pin, photo: request.photo)
        }
        .sheet(isPresented: $session.showSettings) { RoomSettingsSheet(room: room) }
        .sheet(isPresented: $session.showGoals) { RoomGoalsSheet(room: room) }
        .fullScreenCover(isPresented: $session.showScan) {
            ScanFlowView { result, captured in
                ScanActions.apply(result, captured: captured, to: room, items: items, sync: sync)
                sync.activity = ActivityEvent(text: ScanCopy.found(result.objects.count), symbol: "viewfinder", status: nil)
            }
        }
        .environment(session)
        .captureConsent(for: room, isHost: room.role(of: sync.userId) == .host)
        .onAppear {
            #if DEBUG
            if DemoData.asGuest { session.previewAsGuest = true }
            #endif
            keepTabVisible()
            if pendingInvite.wrappedValue == room.id {
                pendingInvite.wrappedValue = nil
                session.showInviteOnPeople = true
                router.roomTab = .people
            }
        }
    }

    /// If the tab on screen belongs to a goal that's off, go to the room's first goal instead.
    private func keepTabVisible() {
        if !tabs.contains(router.roomTab) { router.roomTab = RoomTab.start(for: room) }
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
