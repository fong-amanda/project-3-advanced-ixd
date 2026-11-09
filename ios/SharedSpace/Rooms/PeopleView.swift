import SwiftData
import SwiftUI

/// People tab: who's in the room, inviting the guest, and the room code.
/// Inviting is optional; Sort works fine solo.
struct PeopleView: View {
    let room: Room
    @Environment(SyncEngine.self) private var sync
    @Environment(RoomSession.self) private var session
    @Query private var items: [Item]
    @State private var showAddGuest = false
    @State private var copied = false

    init(room: Room) {
        self.room = room
        _items = Query(Item.live(in: room.id))
    }

    private var context: RoomContext { session.context(room, userId: sync.userId) }
    private var guest: String { room.name(of: .guest) }

    var body: some View {
        List {
            Section("In this room") {
                personRow(.host)
                if room.hasGuest {
                    personRow(.guest)
                } else if context.canEditRoom {
                    Button { showAddGuest = true } label: {
                        Label("Add a person", systemImage: "person.badge.plus")
                    }
                }
            }

            if context.canEditRoom && !room.hasGuest {
                Section {
                    Text("If some things here belong to someone else, add them so they can decide on their own things. This is optional; you can sort on your own.")
                        .font(.subheadline)
                        .foregroundStyle(Color.ssInk2)
                }
            }

            if context.canEditRoom && room.hasGuest && !room.guestHasJoined {
                Section {
                    if sync.isShared {
                        ShareLink(item: inviteMessage) {
                            Label(room.invitedAt == nil ? "Invite \(guest)" : "Invite \(guest) again",
                                  systemImage: "square.and.arrow.up")
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            room.invitedAt = .now
                            sync.save(room)
                        })
                    }
                    Button("Change name") { showAddGuest = true }
                } footer: {
                    Text("Until \(guest) joins, you can decide for them in Sort.")
                }
            }

            Section {
                if sync.isShared {
                    HStack {
                        Text(room.code)
                            .font(.system(size: 30, weight: .regular, design: .serif))
                            .kerning(5)
                            .textSelection(.enabled)
                        Spacer()
                        Button(copied ? "Copied" : "Copy") {
                            UIPasteboard.general.string = room.code
                            copied = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                } else {
                    Label("Sharing is off in this build, so the room stays on this iPhone.", systemImage: "icloud.slash")
                        .font(.subheadline)
                        .foregroundStyle(Color.ssInk2)
                }
            } header: {
                Text("Room code")
            } footer: {
                if sync.isShared {
                    Text("Anyone with this code can open Shared Space, tap “I’m invited” and join as the second person.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ssBg)
        .roomChrome(room)
        .sheet(isPresented: $showAddGuest) { AddGuestSheet(room: room) }
    }

    private func personRow(_ role: Role) -> some View {
        let name = room.name(of: role)
        let isMe = role == context.realRole
        let userId = role == .host ? room.hostUserId : room.guestUserId
        let theirs = SortRules.items(items, belongingTo: role).count
        return HStack(spacing: 12) {
            Avatar(name: name, role: role,
                   online: isMe || !sync.isShared ? nil : (userId == nil ? false : sync.isPresent(userId)))
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "\(name) (you)" : name).font(.body.weight(.semibold))
                Text(statusLine(role, isMe: isMe, theirs: theirs)).font(.subheadline).foregroundStyle(Color.ssMuted)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusLine(_ role: Role, isMe: Bool, theirs: Int) -> String {
        let whose = isMe ? "yours" : "theirs"
        let things = theirs == 0 ? "" : ". \(theirs) thing\(theirs == 1 ? " is" : "s are") \(whose) or shared"
        if role == .host { return (isMe ? "You set up this room" : "Set up this room") + things }
        if room.guestHasJoined { return (sync.isPresent(room.guestUserId) && !isMe ? "Here now" : "Has joined") + things }
        if room.invitedAt != nil { return "Invite sent, not joined yet" + things }
        return (sync.isShared ? "Not invited yet" : "Sorting on this phone only") + things
    }

    private var inviteMessage: String {
        let theirs = SortRules.items(items, belongingTo: .guest).count
        let count = theirs > 0 ? " (\(theirs) so far)" : ""
        let place = room.currentUse.isEmpty ? room.name.lowercased() : room.currentUse.lowercased()
        let becoming = room.futureUse.isEmpty ? "" : " into a \(room.futureUse.lowercased())"
        return """
        Hi \(guest)! I’m turning the \(place)\(becoming). Some of your things are still in there\(count). \
        Could you tell me what you’d like to happen to them?

        Open this link, or open Shared Space and enter the code \(room.code):
        \(Backend.joinURL(code: room.code).absoluteString)
        """
    }
}

/// Name the second person (before they join).
struct AddGuestSheet: View {
    let room: Room
    var onSaved: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("For example, Sam", text: $name).textContentType(.givenName)
                } header: {
                    Text("Their first name")
                } footer: {
                    Text("They can join with the room code and decide on their own things. Their name is used everywhere in the app.")
                }
            }
            .navigationTitle("Who else has things here?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        room.guestName = name.trimmed
                        sync.save(room)
                        onSaved?()
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
            .onAppear { name = room.guestName ?? "" }
        }
        .presentationDetents([.medium])
    }
}
