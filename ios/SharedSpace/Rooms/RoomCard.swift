import SwiftUI

/// A room on the home screen: thumbnail, name, "now → becoming", and where things stand.
struct RoomCard: View {
    let room: Room
    let me: Role
    /// The room Sort, Redesign and People are showing.
    var isCurrent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name).font(.display(22)).foregroundStyle(Color.ssInk)
                if !room.transformLine.isEmpty {
                    Text(room.transformLine).font(.subheadline).foregroundStyle(Color.ssInk2)
                }
                HStack(spacing: 6) {
                    Tag(text: statusText)
                    if isCurrent {
                        Tag(text: "Current room", symbol: "checkmark", foreground: .ssKeep, background: .ssKeepSoft)
                    }
                }
                .padding(.top, 6)
            }
            .padding(16)
        }
        .background(Color.ssSurface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ssLine))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = UIImage(contentsOfFile: FileStore.thumbnailURL(room.id).path()) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Color.ssStage
                Image(systemName: room.isScanned ? "cube.transparent" : "square.dashed")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.ssMuted)
            }
        }
    }

    private var statusText: String {
        if me == .guest { return "Invited by \(room.name(of: .host))" }
        let items = room.liveItems
        let progress = SortProgress(items)
        var parts: [String] = []
        if items.isEmpty {
            parts.append(room.isScanned ? "Scanned" : "Getting started")
        } else {
            parts.append(progress.isComplete ? "All decided" : "\(progress.undecided) to decide")
        }
        let designs = room.liveDesigns.count
        if designs > 0 { parts.append("\(designs) design\(designs == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
