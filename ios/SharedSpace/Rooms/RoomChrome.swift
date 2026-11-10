import SwiftUI

/// Top bar shared by both tabs of a room: back to Rooms, the room name, and the ⋯ menu
/// (People & sharing, Room details). Also shows a banner while the host previews the guest's view.
struct RoomChrome<Trailing: View>: ViewModifier {
    let room: Room
    @ViewBuilder var trailing: Trailing
    @Environment(SyncEngine.self) private var sync
    @Environment(Router.self) private var router
    @Environment(RoomSession.self) private var session
    @State private var confirmDelete = false

    private var realRole: Role { room.role(of: sync.userId) }

    func body(content: Content) -> some View {
        content
            .appNavigation(room.name, large: true)
            .navigationBarBackButtonHidden()
            .toolbar {
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
                Text(realRole == .host ? "This removes the room, its things and plans from both phones." :
                        "You can rejoin later with the room code.")
            }
    }

    private var menu: some View {
        Menu {
            Button("People & sharing", systemImage: "person.2") { session.show(.people, on: router.roomTab) }
            if realRole == .host && !session.previewAsGuest {
                Button("Room details", systemImage: "pencil") { session.showSettings = true }
            }
            if realRole == .host && room.hasGuest {
                Button(session.previewAsGuest ? "Switch back to my view" : "View as \(room.name(of: .guest))",
                       systemImage: "eye") { togglePreview() }
            }
            if !session.previewAsGuest {
                Divider()
                Button(realRole == .host ? "Delete room" : "Leave room",
                       systemImage: realRole == .host ? "trash" : "rectangle.portrait.and.arrow.right",
                       role: .destructive) { confirmDelete = true }
            }
        } label: {
            ToolbarIcon(symbol: "ellipsis")
        }
        .accessibilityLabel("Room options")
    }

    private var previewBanner: some View {
        let guest = room.name(of: .guest)
        return HStack(spacing: Space.m) {
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
        withAnimation {
            session.previewAsGuest.toggle()
            router.roomTab = .items
        }
    }
}

extension View {
    func roomChrome(_ room: Room) -> some View { modifier(RoomChrome(room: room) { EmptyView() }) }
    func roomChrome<T: View>(_ room: Room, @ViewBuilder trailing: () -> T) -> some View {
        modifier(RoomChrome(room: room, trailing: trailing))
    }
}
