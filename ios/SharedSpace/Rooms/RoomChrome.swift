import SwiftUI

/// Top bar shared by every tab of a room: back to Rooms, the room name, and the ⋯ menu
/// (Room goals…, Room details, Delete Room… for the host, Leave Room… for the guest).
/// Also shows a banner while the host previews the guest's view.
struct RoomChrome<Trailing: View>: ViewModifier {
    let room: Room
    @ViewBuilder var trailing: Trailing
    @Environment(SyncEngine.self) private var sync
    @Environment(Router.self) private var router
    @Environment(RoomSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var deleting: Room?
    @State private var leaving: Room?
    @State private var showAccessibilityCheck = false
    @State private var showDesignSystem = false

    private var realRole: Role { room.role(of: sync.userId) }

    func body(content: Content) -> some View {
        content
            // The system large title can't wrap, so at accessibility text sizes the room's name is
            // shown as a wrapping heading instead of being cut off ("Alex's old ro…").
            .appNavigation(room.name, large: !typeSize.isAccessibilitySize)
            .navigationBarBackButtonHidden()
            .toolbar {
                if typeSize.isAccessibilitySize {
                    ToolbarItem(placement: .principal) { Color.clear.accessibilityHidden(true) }
                }
                ToolbarItem(placement: .topBarLeading) {
                    BackButton(label: "Back to rooms") { router.closeRoom() }
                }
                .plainToolbarBackground()
                ToolbarItemGroup(placement: .topBarTrailing) {
                    trailing
                    menu
                }
            }
            .safeAreaInset(edge: .top, spacing: Space.xs) {
                VStack(spacing: 0) {
                    if typeSize.isAccessibilitySize {
                        Text(room.name)
                            .font(.largeTitleText)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.page)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if session.previewAsGuest { previewBanner }
                }
            }
            .roomRemoval(deleting: $deleting, leaving: $leaving)
            #if DEBUG
            .sheet(isPresented: $showAccessibilityCheck) { AccessibilityCheckView() }
            .fullScreenCover(isPresented: $showDesignSystem) { DesignSystemGallery() }
            .onAppear { if DemoData.openAccessibilityCheck { showAccessibilityCheck = true } }
            #endif
    }

    private var menu: some View {
        Menu {
            if realRole == .host && !session.previewAsGuest {
                Button("Room goals…", systemImage: "target") { session.showGoals = true }
                Button("Room details", systemImage: "pencil") { session.showSettings = true }
            }
            Button("People & sharing", systemImage: "person.2") { router.roomTab = .people }
            if realRole == .host && room.hasGuest {
                Button(session.previewAsGuest ? "Switch back to my view" : "View as \(room.name(of: .guest))",
                       systemImage: "eye") { togglePreview() }
            }
            #if DEBUG
            Button("Design system", systemImage: "paintpalette") { showDesignSystem = true }
            Button("Accessibility check", systemImage: "checkmark.seal") { showAccessibilityCheck = true }
            #endif
            if !session.previewAsGuest {
                Divider()
                if realRole == .host {
                    Button("Delete Room…", systemImage: "trash", role: .destructive) { deleting = room }
                } else {
                    Button("Leave Room…", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { leaving = room }
                }
            }
        } label: {
            ToolbarIcon(symbol: "ellipsis")
        }
        .accessibilityLabel("Room options")
    }

    private var previewBanner: some View {
        let guest = room.name(of: .guest)
        return AdaptiveStack(spacing: Space.m) {
            Image(systemName: "eye").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Viewing as \(guest)").font(.detailStrong)
                Text(session.isReadOnly(in: room) ? "Only \(guest) can change their things."
                                                  : "Decisions you make here count as \(guest)’s.")
                    .font(.detail)
            }
            Spacer()
            Button("Switch back") { togglePreview() }
                .buttonStyle(.app(.neutral, size: .compact))
        }
        .foregroundStyle(Tone.sage.text)
        .padding(.horizontal, Space.page).padding(.vertical, Space.s)
        .background(Tone.sage.fill)
    }

    private func togglePreview() {
        withMotion(reduceMotion: reduceMotion, fade: true) {
            session.previewAsGuest.toggle()
            router.roomTab = room.sortEnabled ? .items : .room
        }
    }
}

extension View {
    func roomChrome(_ room: Room) -> some View { modifier(RoomChrome(room: room) { EmptyView() }) }
    func roomChrome<T: View>(_ room: Room, @ViewBuilder trailing: () -> T) -> some View {
        modifier(RoomChrome(room: room, trailing: trailing))
    }
}

// MARK: - Delete and leave (used by the room's ⋯ menu and by Home)

/// The confirmations for "Delete Room…" (host) and "Leave Room…" (guest), and what happens after.
private struct RoomRemoval: ViewModifier {
    @Binding var deleting: Room?
    @Binding var leaving: Room?
    @Environment(SyncEngine.self) private var sync
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        content
            // Host only: deletes the room and everything in it, here and on the server.
            .confirmationDialog("Delete this room?", isPresented: present($deleting), titleVisibility: .visible,
                                presenting: deleting) { room in
                Button("Delete Room", role: .destructive) { delete(room) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This permanently removes the room, its scan and photo, every item and decision, all designs, and the room code. This can’t be undone.")
            }
            .confirmationDialog("Leave \(leaving?.name ?? "room")?", isPresented: present($leaving), titleVisibility: .visible,
                                presenting: leaving) { room in
                Button("Leave Room", role: .destructive) {
                    Task {
                        await sync.leave(room)
                        router.closeRoom()
                    }
                }
            } message: { _ in
                Text("It’s removed from this phone. You can rejoin later with the room code.")
            }
    }

    private func present(_ target: Binding<Room?>) -> Binding<Bool> {
        Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } })
    }

    private func delete(_ room: Room) {
        // Read everything needed afterwards now: the room object is gone once it's deleted.
        let guest = room.hasGuest ? room.name(of: .guest) : nil
        Task {
            let outcome = await sync.deleteRoom(room)
            router.closeRoom()
            switch outcome {
            case .deleted:
                sync.activity = ActivityEvent(text: "Room deleted", symbol: "trash", status: nil)
            case .queued:
                router.notice = Router.Notice(
                    title: "Deleted from this phone",
                    message: "You’re offline, so the room will be removed from the server\(guest.map { " and from \($0)’s phone" } ?? "") as soon as you’re back online.")
            }
        }
    }
}

extension View {
    func roomRemoval(deleting: Binding<Room?>, leaving: Binding<Room?>) -> some View {
        modifier(RoomRemoval(deleting: deleting, leaving: leaving))
    }
}
