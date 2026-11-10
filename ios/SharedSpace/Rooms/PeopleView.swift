import SwiftData
import SwiftUI

/// People & sharing (from the room's ⋯ menu): who's in the room, inviting someone, the room code.
/// Inviting is optional; a room works fine solo.
struct PeopleView: View {
    let room: Room
    @Environment(SyncEngine.self) private var sync
    @Environment(RoomSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [Item]
    @State private var showAddGuest = false
    @State private var showInvite = false
    @State private var copied = false

    init(room: Room) {
        self.room = room
        _items = Query(Item.live(in: room.id))
    }

    private var context: RoomContext { session.context(room, userId: sync.userId) }
    private var isHost: Bool { context.realRole == .host }
    private var guest: String { room.name(of: .guest) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(spacing: Space.xs) {
                    personRow(.host)
                    if room.hasGuest {
                        Hairline(inset: Space.l + Size.avatar + Space.m)
                        personRow(.guest)
                    } else if isHost {
                        Hairline(inset: Space.l)
                        Button { showAddGuest = true } label: { Label("Invite someone", systemImage: "plus") }
                            .buttonStyle(.app(.primary))
                            .padding(Space.l)
                    }
                }
                .listGroup()

                if room.hasGuest {
                    let theirs = items.filter { $0.owner == .guest }.count
                    Text("\(theirs) of \(items.count) things are \(SortRules.possessive(guest))")
                        .textRole(.secondary)
                }

                if isHost && room.hasGuest && !room.guestHasJoined && sync.isShared {
                    Button { showInvite = true } label: {
                        Label(room.invitedAt == nil ? "Invite \(guest)" : "Invite \(guest) again", systemImage: "paperplane")
                    }
                    .buttonStyle(.app(.primary))
                }

                if sync.isShared {
                    KVRow(label: "Room code", value: room.code, valueFont: .codeSmall, tracking: Tracking.code) {
                        Button(copied ? "Copied" : "Copy") {
                            UIPasteboard.general.string = room.code
                            copied = true
                        }
                        .buttonStyle(.app(.primary, size: .compact))
                    }
                    .accessibilityHint("Anyone with this code can join as the second person")
                } else {
                    Label("Sharing is off in this build, so the room stays on this iPhone.", systemImage: "icloud.slash")
                        .textRole(.secondary)
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    if isHost && !session.previewAsGuest {
                        Button { session.showSettings = true } label: { Label("Room details", systemImage: "pencil") }
                            .buttonStyle(.app(.primary, size: .compact))
                    }
                    if isHost && room.hasGuest {
                        Button {
                            session.previewAsGuest.toggle()
                            session.itemsPath = []
                            session.planPath = []
                            router.roomTab = .items
                        } label: {
                            Label(session.previewAsGuest ? "Switch back to my view" : "View as \(guest)", systemImage: "eye")
                        }
                        .buttonStyle(.app(.primary, size: .compact))
                    }
                    if isHost && room.hasGuest && !room.guestHasJoined {
                        Button { showAddGuest = true } label: { Label("Change their name", systemImage: "person") }
                            .buttonStyle(.app(.primary, size: .compact))
                    }
                }
            }
            .pagePadding()
            .padding(.bottom, Size.floatingClearance)
        }
        .pageBackground()
        .appNavigation("People & sharing", large: true)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { BackButton { dismiss() } }
                .plainToolbarBackground()
        }
        .sheet(isPresented: $showAddGuest) {
            AddGuestSheet(room: room, items: items) { if sync.isShared { showInvite = true } }
        }
        .sheet(isPresented: $showInvite) { InviteSheet(room: room, items: items) }
        .onAppear {
            if session.showInviteOnPeople {
                session.showInviteOnPeople = false
                if sync.isShared { showInvite = true }
            }
        }
    }

    private func personRow(_ role: Role) -> some View {
        let name = room.name(of: role)
        let isMe = role == context.realRole
        let userId = role == .host ? room.hostUserId : room.guestUserId
        return HStack(spacing: Space.m) {
            Avatar(name: name, role: role,
                   online: isMe || !sync.isShared ? nil : (userId == nil ? false : sync.isPresent(userId)))
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(isMe ? "\(name) (you)" : name).textRole(.bodyStrong)
                Text(statusLine(role, isMe: isMe)).textRole(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
    }

    private func statusLine(_ role: Role, isMe: Bool) -> String {
        if role == .host { return "Owner" }
        if room.guestHasJoined { return sync.isPresent(room.guestUserId) && !isMe ? "Here now" : "Joined" }
        if room.invitedAt != nil { return "Invited" }
        return sync.isShared ? "Not invited yet" : "Sorting on this phone only"
    }
}

/// Name the second person, and say whose things are in the room so owners are set in one go.
struct AddGuestSheet: View {
    let room: Room
    let items: [Item]
    var onSaved: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @State private var name = ""
    @State private var things: Things = .theirs

    enum Things: String, CaseIterable { case theirs = "Theirs", mine = "Mine", mixed = "Mixed" }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    SectionLabel("Their first name")
                    TextField("For example, Alex", text: $name).textContentType(.givenName).textFieldStyle(.app)
                }
                if !room.hasGuest {
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Whose things are in this room?")
                        ChipPicker(options: Things.allCases.map { .init(value: $0, title: $0.rawValue) }, selection: $things)
                    }
                }
                Button(name.trimmed.isEmpty ? "Add person" : "Add \(name.trimmed)", action: save)
                    .buttonStyle(.app)
                    .disabled(name.trimmed.isEmpty)
                Spacer()
            }
            .padding(Space.page)
            .appSheet()
            .appNavigation(room.hasGuest ? "Change their name" : "Invite someone")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { name = room.guestName ?? "" }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let first = !room.hasGuest
        room.guestName = name.trimmed
        sync.save(room)
        if first {
            // Like the prototype: "Theirs" hands every undecided thing to them; otherwise unowned things become yours.
            for item in items where item.owner == .unassigned || (things == .theirs && !item.isDecided && item.owner == .host) {
                item.owner = things == .theirs ? .guest : .host
                sync.save(item)
            }
        }
        dismiss()
        if first { onSaved?() }
    }
}

/// The invite: the room code and a message to send any way you like.
struct InviteSheet: View {
    let room: Room
    let items: [Item]
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @State private var message = ""
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Send \(room.name(of: .guest)) this message any way you like. They open Shared Space, tap Join with a code, and type it in.")
                        .textRole(.secondary)
                    VStack(spacing: Space.xs) {
                        Text("Room code").textRole(.secondary)
                        Text(room.code).font(.code).kerning(Tracking.code).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity)
                    .card(padding: Space.m)
                    .accessibilityElement(children: .combine)
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Message")
                        TextField("Message", text: $message, axis: .vertical)
                            .lineLimit(4...10)
                            .textFieldStyle(.appArea)
                    }
                    HStack(spacing: Space.m) {
                        ShareLink(item: message) { Label("Send", systemImage: "paperplane") }
                            .buttonStyle(.app)
                            .simultaneousGesture(TapGesture().onEnded { markInvited() })
                        Button {
                            UIPasteboard.general.string = message
                            copied = true
                            markInvited()
                        } label: { Label(copied ? "Copied" : "Copy message", systemImage: "doc.on.doc") }
                            .buttonStyle(.app(.neutral))
                    }
                }
                .padding(Space.page)
            }
            .appSheet()
            .appNavigation("Invite \(room.name(of: .guest))")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if message.isEmpty { message = defaultMessage } }
        }
    }

    private func markInvited() {
        room.invitedAt = .now
        sync.save(room)
    }

    private var defaultMessage: String {
        let theirs = SortRules.items(items, belongingTo: .guest).count
        let becoming = room.futureUse.isEmpty || room.futureUse == "Still deciding" ? "" : " to make it a \(room.futureUse.lowercased())"
        let still = theirs > 0 ? "\(theirs) of your things are still in there. " : ""
        return """
        Hi \(room.name(of: .guest)), I’m sorting out the \(room.name.lowercased())\(becoming). \(still)\
        Could you say what should happen to them? Open Shared Space and enter the code \(room.code), or open this link:
        \(Backend.joinURL(code: room.code).absoluteString)
        """
    }
}
