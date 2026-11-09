import SwiftUI

/// A room on the home screen. Works out the photo and status line, then uses the shared RoomCard.
struct RoomSummaryCard: View {
    let room: Room
    let me: Role
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        RoomCard(name: room.name, plannedUse: room.futureUse, status: statusText,
                 image: RoomPhotos.image(roomId: room.id, index: 0, revision: sync.photoRevision)
                    ?? UIImage(contentsOfFile: FileStore.thumbnailURL(room.id).path()),
                 tint: me == .guest ? .accent : .highlight)
    }

    /// Matches the prototype: "4 waiting for Alex, 1 for you", "3 of 7 to decide", "All decided, 2 leaving".
    private var statusText: String {
        if me == .guest { return "Shared by \(room.name(of: .host))" }
        let items = room.liveItems
        guard !items.isEmpty else { return "Nothing listed yet" }
        let progress = SortProgress(items)
        let waiting = items.filter { !$0.isDecided && $0.owner == .guest }.count
        if waiting > 0 && room.hasGuest {
            let mine = progress.undecided - waiting
            return "\(waiting) waiting for \(room.name(of: .guest))" + (mine > 0 ? ", \(mine) for you" : "")
        }
        if progress.undecided > 0 { return "\(progress.undecided) of \(progress.total) to decide" }
        return progress.leaving > 0 ? "All decided, \(progress.leaving) leaving" : "All decided"
    }
}
