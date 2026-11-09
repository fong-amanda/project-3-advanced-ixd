import SwiftData
import SwiftUI

@main
struct SharedSpaceApp: App {
    private let container: ModelContainer
    @State private var sync: SyncEngine
    @State private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Room.self, Item.self, Design.self, DesignPlacement.self)
        } catch {
            fatalError("Couldn’t open the local database: \(error)")
        }
        self.container = container
        _sync = State(initialValue: SyncEngine(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sync)
                .environment(router)
                .modelContainer(container)
                .tint(.ssInk)
                .task {
                    #if DEBUG
                    if DemoData.requested {
                        router.openRoom(DemoData.room(sync: sync).id, showing: DemoData.asGuest ? .sort : (DemoData.requestedTab ?? .home))
                    }
                    #endif
                    await sync.start()
                }
                .onOpenURL { url in
                    if let code = Backend.roomCode(from: url) { router.joinRequest = JoinRequest(code: code) }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL, let code = Backend.roomCode(from: url) {
                        router.joinRequest = JoinRequest(code: code)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await sync.refresh() } }
                }
        }
    }
}
