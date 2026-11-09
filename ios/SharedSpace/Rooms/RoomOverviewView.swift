import SwiftData
import SwiftUI

/// Room tab: what the room is, how big it is, scan it, and the things in it.
struct RoomOverviewView: View {
    let room: Room
    @Environment(SyncEngine.self) private var sync
    @Environment(RoomSession.self) private var session
    @Query private var items: [Item]
    @State private var selected: Item?

    init(room: Room) {
        self.room = room
        _items = Query(Item.live(in: room.id))
    }

    private var context: RoomContext { session.context(room, userId: sync.userId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                preview
                details
                if context.canEditRoom { actions }
                things
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.ssBg)
        .roomChrome(room)
        .sheet(item: $selected) { item in ItemDetailSheet(item: item, room: room) }
    }

    // MARK: Sections

    @ViewBuilder private var preview: some View {
        Group {
            if let image = UIImage(contentsOfFile: FileStore.thumbnailURL(room.id).path()) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if !items.isEmpty {
                FloorPlanView(room: room, entries: items.map { PlanEntry(actual: $0) }, showLabels: true)
                    .padding(16)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "square.dashed").font(.system(size: 40, weight: .light))
                    Text(room.isScanned ? "Scan saved" : "No scan yet").font(.subheadline)
                }
                .foregroundStyle(Color.ssMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .background(Color.ssStage)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityLabel(room.isScanned ? "Room scan preview" : "Room floor plan")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(room.name).font(.display(30))
            if !room.transformLine.isEmpty {
                Text(room.transformLine).foregroundStyle(Color.ssInk2)
            }
            Label(sizeLine, systemImage: "ruler")
                .font(.subheadline)
                .foregroundStyle(Color.ssMuted)
        }
    }

    private var sizeLine: String {
        let m = { (cm: Int) in (Double(cm) / 100).formatted(.number.precision(.fractionLength(0...2))) }
        let source = room.isScanned ? "from your scan" : "set by hand"
        return "\(m(room.widthCm)) × \(m(room.lengthCm)) m, \(String(format: "%.1f", room.floorAreaM2)) m², ceiling \(m(room.heightCm)) m, \(source)"
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { session.startScan() } label: {
                Label(room.isScanned ? "Rescan" : "Scan room", systemImage: "viewfinder")
            }
            .buttonStyle(.pill)
            Button { session.showAddItem = true } label: {
                Label("Add items by hand", systemImage: "plus")
            }
            .buttonStyle(.pill(.secondary))
            if !DeviceCapabilities.canScanRooms {
                Text("This iPhone can’t scan rooms (scanning needs LiDAR). Add things by hand and set the size in Room details.")
                    .font(.footnote)
                    .foregroundStyle(Color.ssMuted)
            }
        }
    }

    private var things: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Things in this room").font(.headline)
                Spacer()
                Text("\(items.count)").foregroundStyle(Color.ssMuted)
            }
            if items.isEmpty {
                Text(context.canEditRoom ? "Nothing yet. Scan the room or add things by hand."
                                         : "\(room.name(of: .host)) hasn’t added anything yet.")
                    .font(.subheadline)
                    .foregroundStyle(Color.ssMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        Button { selected = item } label: {
                            HStack(spacing: 12) {
                                ItemThumb(item: item, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.body.weight(.semibold)).foregroundStyle(Color.ssInk)
                                    Text("\(item.category.label), about \(Int(item.widthCm)) × \(Int(item.depthCm)) cm")
                                        .font(.caption).foregroundStyle(Color.ssMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.ssMuted)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if item.id != items.last?.id { Divider() }
                    }
                }
                .ssCard(padding: 12)
            }
        }
    }
}
