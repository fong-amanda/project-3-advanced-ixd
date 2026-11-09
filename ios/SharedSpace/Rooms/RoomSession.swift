import Observation
import SwiftUI

/// "Add something" request: optionally at a spot the host tapped on a room photo.
struct AddItemRequest: Identifiable {
    let id = UUID()
    var pin: CGPoint?
    var photo = 0
}

/// State for the open room, shared by its Items and Room plan tabs.
@MainActor
@Observable
final class RoomSession {
    /// Host only: see the room the way the guest does ("View as Alex").
    var previewAsGuest = false

    var addItem: AddItemRequest?
    /// LiDAR room scan (RoomPlan). Only offered on phones that can scan.
    var showScan = false
    var showSettings = false
    /// Set when People opens right after creating a room with "Invite someone".
    var showInviteOnPeople = false

    var itemsPath: [RoomRoute] = []
    var planPath: [RoomRoute] = []

    /// The plan version on screen in Room plan (nil = the room as it is now).
    var planDesignId: UUID?
    var planDesignPicked = false

    /// The role the screens should act as (the guest's, while the host previews their view).
    func me(in room: Room, userId: UUID) -> Role {
        let real = room.role(of: userId)
        return real == .host && previewAsGuest ? .guest : real
    }

    /// While previewing a guest who has already joined, only they may change their things.
    func isReadOnly(in room: Room) -> Bool {
        previewAsGuest && room.guestHasJoined
    }

    /// Pushes a screen onto the given tab's stack.
    func show(_ route: RoomRoute, on tab: RoomTab) {
        switch tab {
        case .items: if itemsPath.last != route { itemsPath.append(route) }
        case .plan: if planPath.last != route { planPath.append(route) }
        }
    }
}

/// Everything a screen inside a room needs to know about "who am I here".
struct RoomContext {
    let room: Room
    let me: Role
    let realRole: Role
    let readOnly: Bool

    /// The real host, not previewing: may edit the room itself (photos, things, details, plans).
    var canEditRoom: Bool { realRole == .host && me == .host }
}

extension RoomSession {
    func context(_ room: Room, userId: UUID) -> RoomContext {
        RoomContext(room: room, me: me(in: room, userId: userId), realRole: room.role(of: userId),
                    readOnly: isReadOnly(in: room))
    }
}
