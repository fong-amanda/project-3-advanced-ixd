import SwiftData
import SwiftUI

/// Home tab: your rooms. Tap one to go into it.
struct HomeView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<Room> { $0.deletedAt == nil }, sort: \Room.createdAt, order: .reverse)
    private var rooms: [Room]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleRow
                HStack(spacing: 10) {
                    Button { router.showNewRoom = true } label: { Label("New room", systemImage: "plus") }
                        .buttonStyle(.pill)
                    Button { router.joinRequest = JoinRequest(code: "") } label: { Label("I’m invited", systemImage: "person.2") }
                        .buttonStyle(.pill(.secondary))
                }
                if !sync.isShared { LocalOnlyNotice() }
                if rooms.isEmpty {
                    emptyState
                } else {
                    Text("Your rooms").font(.display(24))
                    LazyVStack(spacing: 16) {
                        ForEach(rooms) { room in
                            NavigationLink(value: HomeRoute.room(room.id)) {
                                RoomCard(room: room, me: room.role(of: sync.userId), isCurrent: room.id == currentId)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.ssBg)
        .navigationTitle("Shared Space")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await sync.refresh() }
    }

    /// The room Sort, Redesign and People are showing.
    private var currentId: UUID? {
        (rooms.first { $0.id == router.currentRoomId } ?? rooms.first)?.id
    }

    /// Large title next to the logo (the system large title can't hold an image).
    private var titleRow: some View {
        HStack(spacing: 12) {
            BrandMark().frame(width: 40, height: 40)
            Text("Shared Space")
                .font(.display(34))
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No rooms yet").font(.display(22))
            Text("Add the room you want to change, or join one you were invited to.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ssInk2)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.ssLine, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
    }
}

struct LocalOnlyNotice: View {
    var body: some View {
        Label {
            Text("Sharing is off in this build, so rooms stay on this iPhone. Add your Supabase keys to Supabase.plist to sort together.")
                .font(.footnote)
        } icon: {
            Image(systemName: "icloud.slash")
        }
        .foregroundStyle(Color.ssInk2)
        .ssCard(padding: 12)
    }
}

/// The two overlapping squares from the prototype's logo.
struct BrandMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 32
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4 * s).fill(Color.ssHost)
                    .frame(width: 16 * s, height: 16 * s).offset(x: 3 * s, y: 7 * s)
                RoundedRectangle(cornerRadius: 4 * s).fill(Color(hex: "#F0B03C"))
                    .frame(width: 16 * s, height: 16 * s).offset(x: 13 * s, y: 11 * s)
                Rectangle().fill(Color(hex: "#1D2A25").opacity(0.55))
                    .frame(width: 6 * s, height: 12 * s).offset(x: 13 * s, y: 11 * s)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
