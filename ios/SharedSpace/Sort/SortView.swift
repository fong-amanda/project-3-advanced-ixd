import SwiftData
import SwiftUI

/// Sort tab ("Your things" for the guest). Works with or without a scan; can be used solo.
struct SortView: View {
    let room: Room
    @Environment(SyncEngine.self) private var sync
    @Environment(RoomSession.self) private var session
    @Query private var items: [Item]
    @State private var mode: Mode?
    @State private var filter: Filter = .all
    @State private var selected: Item?
    @State private var showSummary = false

    enum Mode { case list, cards }

    enum Filter: Hashable { case all, toDecide, mine, theirs, shared, unassigned }

    init(room: Room) {
        self.room = room
        _items = Query(Item.live(in: room.id))
    }

    private var context: RoomContext { session.context(room, userId: sync.userId) }
    private var me: Role { context.me }
    /// Guests default to reviewing their own things one at a time.
    private var currentMode: Mode { mode ?? (me == .guest ? .cards : .list) }
    /// What this person is responsible for deciding.
    private var relevant: [Item] { me == .guest ? SortRules.items(items, belongingTo: .guest) : items }
    private var undecided: Int { relevant.filter { !$0.isDecided }.count }
    /// Cards only show things this person can act on (plus ones that still need an owner).
    private var cardItems: [Item] {
        me == .guest ? relevant
            : items.filter { SortRules.canDecide($0, as: me, in: room) || $0.owner == .unassigned }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                NoItemsYetView(context: context,
                               message: "Scan the room to find the furniture automatically, or add things by hand. Then decide what stays, what moves, what goes back to its owner, and what you let go.")
            } else if currentMode == .cards {
                SortCardsView(room: room, items: cardItems, me: me, readOnly: context.readOnly) {
                    filter = .all
                    mode = .list
                }
            } else {
                list
            }
        }
        .background(Color.ssBg)
        .roomChrome(room)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { mode = currentMode == .list ? .cards : .list }
                    } label: {
                        Image(systemName: currentMode == .list ? "rectangle.stack" : "list.bullet")
                    }
                    .accessibilityLabel(currentMode == .list ? "Review one at a time" : "Show as a list")
                }
            }
        }
        .sheet(item: $selected) { item in ItemDetailSheet(item: item, room: room) }
        .sheet(isPresented: $showSummary) { SortSummarySheet(items: relevant, room: room, me: me) }
        .onChange(of: undecided) { old, new in
            if old > 0 && new == 0 && !relevant.isEmpty { showSummary = true }
        }
    }

    // MARK: List

    private var list: some View {
        List {
            if undecided == 0 && !relevant.isEmpty {
                Section {
                    Button { showSummary = true } label: {
                        Label(me == .guest ? "All your things are decided" : "Everything’s decided",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.ssKeep)
                    }
                }
            }
            if me == .host && items.contains(where: { $0.owner == .unassigned }) {
                Section {
                    Label("Start by saying whose each thing is. Then the owner decides.", systemImage: "person.2")
                        .font(.subheadline)
                        .foregroundStyle(Color.ssInk2)
                }
            }
            Section {
                let shown = filtered
                if shown.isEmpty {
                    Text("Nothing here.").foregroundStyle(Color.ssMuted)
                }
                ForEach(shown) { item in
                    Button { selected = item } label: {
                        ItemRow(item: item, room: room, me: me).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        ForEach(ItemStatus.decisions, id: \.self) { status in
                            Button(status.buttonLabel, systemImage: status.icon) {
                                SortActions.choose(status, for: item, as: me, in: room, sync: sync)
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { filterBar }
        .scrollContentBackground(.hidden)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.filter) { entry in
                    Chip(title: "\(entry.title) \(entry.count)", isOn: filter == entry.filter) { filter = entry.filter }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(Color.ssBg)
    }

    private struct FilterEntry {
        let filter: Filter
        let title: String
        let count: Int
    }

    private var filters: [FilterEntry] {
        var result = [
            FilterEntry(filter: .all, title: "All", count: items.count),
            FilterEntry(filter: .toDecide, title: "To decide", count: items.filter { !$0.isDecided }.count),
            FilterEntry(filter: .mine, title: "Yours", count: items.filter { $0.owner.rawValue == me.rawValue }.count),
        ]
        if room.hasGuest || me == .guest {
            result.append(FilterEntry(filter: .theirs, title: SortRules.possessive(room.name(of: me.other)),
                                      count: items.filter { $0.owner.rawValue == me.other.rawValue }.count))
        }
        result.append(FilterEntry(filter: .shared, title: "Shared", count: items.filter { $0.owner == .shared }.count))
        let unassigned = items.filter { $0.owner == .unassigned }.count
        if unassigned > 0 { result.insert(FilterEntry(filter: .unassigned, title: "No owner yet", count: unassigned), at: 1) }
        return result
    }

    private var filtered: [Item] {
        switch filter {
        case .all: items
        case .toDecide: items.filter { !$0.isDecided }
        case .mine: items.filter { $0.owner.rawValue == me.rawValue }
        case .theirs: items.filter { $0.owner.rawValue == me.other.rawValue }
        case .shared: items.filter { $0.owner == .shared }
        case .unassigned: items.filter { $0.owner == .unassigned }
        }
    }
}
