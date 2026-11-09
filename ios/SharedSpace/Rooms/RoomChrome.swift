import SwiftData
import SwiftUI

/// Top bar shared by every tab's root screen: inline room name, a way back to all rooms,
/// and the ⋯ menu. Also shows a banner while the host previews the guest's view.
struct RoomChrome: ViewModifier {
    let room: Room
    @Query(filter: #Predicate<Room> { $0.deletedAt == nil }, sort: \Room.createdAt, order: .reverse)
    private var rooms: [Room]
    @Environment(SyncEngine.self) private var sync
    @Environment(Router.self) private var router
    @Environment(RoomSession.self) private var session
    @State private var confirmDelete = false

    private var realRole: Role { room.role(of: sync.userId) }

    func body(content: Content) -> some View {
        content
            .navigationTitle(room.name)
            .navigationBarTitleDisplayMode(.inline)
            // Tap the room name to switch rooms.
            .toolbarTitleMenu {
                ForEach(rooms) { other in
                    Button { router.switchRoom(to: other.id) } label: {
                        if other.id == room.id { Label(other.name, systemImage: "checkmark") } else { Text(other.name) }
                    }
                }
                Divider()
                Button("All rooms", systemImage: "house") { router.homePath = []; router.tab = .home }
                Button("New room", systemImage: "plus") { router.showNewRoom = true }
                Button("Join with a code", systemImage: "person.2") { router.joinRequest = JoinRequest(code: "") }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if session.previewAsGuest { previewBanner }
            }
            .confirmationDialog(realRole == .host ? "Delete \(room.name) for everyone?" : "Leave \(room.name)?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(realRole == .host ? "Delete room" : "Leave room", role: .destructive) {
                    Task {
                        await sync.deleteOrLeave(room)
                        router.closeRoom()
                    }
                }
            } message: {
                Text(realRole == .host ? "This removes the room, its items and designs from both phones." :
                        "You can rejoin later with the room code.")
            }
    }

    private var menu: some View {
        Menu {
            if realRole == .host && !session.previewAsGuest {
                Button("Room details", systemImage: "pencil") { session.showSettings = true }
            }
            if sync.isShared {
                Button("Copy room code (\(room.code))", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = room.code
                }
            }
            if realRole == .host && room.hasGuest {
                Button(session.previewAsGuest ? "Switch back to my view" : "View as \(room.name(of: .guest))",
                       systemImage: "arrow.left.arrow.right") { togglePreview() }
            }
            if !session.previewAsGuest {
                Divider()
                Button(realRole == .host ? "Delete room" : "Leave room",
                       systemImage: realRole == .host ? "trash" : "rectangle.portrait.and.arrow.right",
                       role: .destructive) { confirmDelete = true }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Room options")
    }

    private var previewBanner: some View {
        let guest = room.name(of: .guest)
        return HStack(spacing: 10) {
            Image(systemName: "eye")
            VStack(alignment: .leading, spacing: 1) {
                Text("Viewing as \(guest)").font(.subheadline.weight(.semibold))
                Text(session.isReadOnly(in: room) ? "Only \(guest) can change their things."
                                                  : "Decisions you make here count as \(guest)’s.")
                    .font(.caption)
            }
            Spacer()
            Button("Switch back") { togglePreview() }
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(Color.ssAccentInk)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.ssAccentSoft)
    }

    private func togglePreview() {
        withAnimation {
            session.previewAsGuest.toggle()
            if session.previewAsGuest { router.tab = .sort }
        }
    }
}

extension View {
    func roomChrome(_ room: Room) -> some View { modifier(RoomChrome(room: room)) }
}
