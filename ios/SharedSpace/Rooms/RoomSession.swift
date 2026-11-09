import Observation
import SwiftUI

/// State for the current room, shared by the Home, Sort, Redesign and People tabs.
@MainActor
@Observable
final class RoomSession {
    private(set) var roomId: UUID?

    /// Host only: see the room the way the guest does.
    var previewAsGuest = false

    var showScan = false
    var showScanUnsupported = false
    var showAddItem = false
    var showSettings = false
    var redesignPath: [RoomRoute] = []

    /// Clears per-room state when a different room becomes current.
    func reset(for roomId: UUID?) {
        guard roomId != self.roomId else { return }
        self.roomId = roomId
        previewAsGuest = false
        redesignPath = []
    }

    /// The role the screens should act as (the guest's, while the host previews their view).
    func me(in room: Room, userId: UUID) -> Role {
        let real = room.role(of: userId)
        return real == .host && previewAsGuest ? .guest : real
    }

    /// While previewing a guest who has already joined, only they may change their things.
    func isReadOnly(in room: Room) -> Bool {
        previewAsGuest && room.guestHasJoined
    }

    func startScan() {
        if DeviceCapabilities.canScanRooms { showScan = true } else { showScanUnsupported = true }
    }
}

/// Everything a screen inside a room needs to know about "who am I here".
struct RoomContext {
    let room: Room
    let me: Role
    let realRole: Role
    let readOnly: Bool

    /// The real host, not previewing: may edit the room itself (scan, add items, details).
    var canEditRoom: Bool { realRole == .host && me == .host }
}

extension RoomSession {
    func context(_ room: Room, userId: UUID) -> RoomContext {
        RoomContext(room: room, me: me(in: room, userId: userId), realRole: room.role(of: userId),
                    readOnly: isReadOnly(in: room))
    }
}
