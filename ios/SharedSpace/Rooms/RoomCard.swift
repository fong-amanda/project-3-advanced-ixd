import SwiftUI

/// A room on the home screen. Works out the photo and status line, then uses the shared RoomCard.
struct RoomSummaryCard: View {
    let room: Room
    let me: Role
    var tint: Tone = .sage
    var reservesMenuCorner = false
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        RoomCard(name: room.name, plannedUse: room.futureUse, status: statusText,
                 goals: room.goals.map { goal in
                     .init(title: goal.tag, symbol: goal.symbol, tone: goal.tone,
                           status: RoomGoalStatus.text(goal, room: room, items: room.liveItems, designs: room.liveDesigns, me: me))
                 },
                 progress: room.sortEnabled ? progress : nil,
                 image: RoomPhotos.image(roomId: room.id, index: 0, revision: sync.photoRevision)
                    ?? UIImage(contentsOfFile: FileStore.thumbnailURL(room.id).path(percentEncoded: false)),
                 tint: tint, reservesMenuCorner: reservesMenuCorner)
    }

    /// Share of things decided, for the bar. None until something is listed.
    private var progress: Double? {
        let items = me == .guest ? SortRules.items(room.liveItems, belongingTo: .guest) : room.liveItems
        guard !items.isEmpty else { return nil }
        return Double(items.filter(\.isDecided).count) / Double(items.count)
    }

    /// Who's waiting on whom, when it matters: "4 waiting for Alex, 1 for you". The goal lines below
    /// the name carry the counts ("7 of 11 decided"), so this is often empty.
    private var statusText: String {
        if me == .guest { return "Shared by \(room.name(of: .host))" }
        guard room.sortEnabled else { return "" }
        let items = room.liveItems
        guard !items.isEmpty else { return "" }
        let progress = SortProgress(items)
        let waiting = items.filter { !$0.isDecided && $0.owner == .guest }.count
        if waiting > 0 && room.hasGuest {
            let mine = progress.undecided - waiting
            return "\(waiting) waiting for \(room.name(of: .guest))" + (mine > 0 ? ", \(mine) for you" : "")
        }
        return progress.undecided == 0 && progress.leaving > 0 ? "\(progress.leaving) leaving the room" : ""
    }
}
