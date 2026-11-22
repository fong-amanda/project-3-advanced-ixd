import PhotosUI
import SwiftData
import SwiftUI

/// Items tab. The room photo with numbered pins on top, then one list split into
/// "For you to decide", "Waiting for Alex" and "Decided". The invited person starts on
/// one-at-a-time cards. Works solo, and without any photo.
struct ItemsView: View {
    let room: Room
    @Environment(SyncEngine.self) private var sync
    @Environment(RoomSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.captureConsent) private var consent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var items: [Item]

    @State private var view: Bucket = .needs
    @State private var filter = ItemFilter()
    @State private var showFilter = false
    @State private var stage: Stage = .photo
    @State private var photoIndex = 0
    @State private var selectedId: UUID?
    @State private var detailItem: Item?
    @State private var selecting = false
    @State private var selectedIds: Set<UUID> = []
    @State private var cards: Bool?
    @State private var skipped: [UUID] = []
    @State private var showSummary = false
    @State private var showZoom = false
    @State private var findIn: PhotoToSearch?
    /// Rows opened one at a time with their chevron.
    @State private var expanded: Set<UUID> = []
    /// Rows closed by hand while "Expand all" is on.
    @State private var collapsed: Set<UUID> = []
    /// Where each thing sits, fixed when the list is grouped. A decision changes a row's tag,
    /// never its place: things move to "Decided" only when the person comes back to Sort,
    /// changes tab or filter, or pulls to refresh.
    @State private var arrangement: Arrangement?
    /// "Hide decided": decided here and still on screen, until the person moves on from them.
    @State private var pendingHide: Set<UUID> = []
    /// "Hide decided": moved on from, so hidden until the next regroup.
    @State private var movedOn: Set<UUID> = []
    /// Fading out before they're taken out of the list.
    @State private var fading: Set<UUID> = []
    /// The thing just deleted, for "Item deleted. Undo".
    @State private var justDeleted: Item?
    /// The decision just made, for "Marked “Keep”. Undo".
    @State private var decisionBanner: DecisionUndo?
    /// Row positions on screen, so changes above or inside a row don't move the rows being read.
    @State private var frames = RowFrames()

    private struct PhotoToSearch: Identifiable {
        let id = UUID()
        let index: Int
        let image: UIImage
    }

    enum Bucket: Hashable { case needs, waiting, decided }

    private struct Arrangement {
        var order: [UUID: Int] = [:]
        var bucket: [UUID: Bucket] = [:]
        /// Passed the filter when grouped, so a decision never drops a row from a filtered list.
        var passes: Set<UUID> = []
    }
    enum Stage: Hashable { case photo, model }

    init(room: Room) {
        self.room = room
        _items = Query(Item.live(in: room.id))
    }

    private var context: RoomContext { session.context(room, userId: sync.userId) }
    private var me: Role { context.me }
    private var photos: [Int] { RoomPhotos.available(room, revision: sync.photoRevision) }
    private var queue: [Item] { SortRules.queue(items, me: me, in: room, skipped: skipped) }
    /// The invited person starts on cards when something needs them.
    private var showingCards: Bool { (cards ?? (me == .guest)) && !queue.isEmpty }
    /// Things this person answers for (the summary counts these).
    private var relevant: [Item] { me == .guest ? SortRules.items(items, belongingTo: .guest) : items }
    private var openCount: Int { relevant.filter { !$0.isDecided }.count }

    var body: some View {
        Group {
            if items.isEmpty && photos.isEmpty {
                emptyState
            } else if showingCards {
                SortCardsView(room: room, queue: queue, total: cardTotal, me: me, readOnly: context.readOnly,
                              skipped: $skipped)
            } else {
                list
            }
        }
        .pageBackground()
        .roomChrome(room) {
            if !queue.isEmpty {
                Button {
                    withMotion(reduceMotion: reduceMotion, fade: true) { cards = !showingCards }
                } label: {
                    ToolbarIcon(symbol: showingCards ? "list.bullet" : "rectangle.stack")
                }
                .accessibilityLabel(showingCards ? "Show as a list" : "One at a time")
            }
        }
        .sheet(item: $detailItem) { item in ItemDetailSheet(item: item, room: room) }
        #if DEBUG
        .task {
            guard DemoData.openItemSheet else { return }
            try? await Task.sleep(for: .milliseconds(600))
            detailItem = items.first { !$0.isDecided } ?? items.first
        }
        .task {
            if DemoData.expandAllItems { session.expandAllItems = true }
            if DemoData.scrollList {
                try? await Task.sleep(for: .milliseconds(800))
                selectedId = items.sorted { SortRules.rank($0, me: me, in: room) < SortRules.rank($1, me: me, in: room) }.first?.id
            }
        }
        .task {
            guard DemoData.openFindThings else { return }
            try? await Task.sleep(for: .milliseconds(600))
            if let image = RoomPhotos.image(roomId: room.id, index: 0, revision: sync.photoRevision) {
                findIn = PhotoToSearch(index: 0, image: image)
            }
        }
        #endif
        .sheet(isPresented: $showFilter) { FilterSheet(room: room, me: me, filter: $filter) }
        .sheet(isPresented: $showSummary) {
            SortSummarySheet(items: relevant, room: room, me: me) { router.roomTab = room.planEnabled ? .plan : .room }
        }
        .sheet(item: $findIn) { target in
            DetectionReviewSheet(image: target.image, existing: existingThings(on: target.index)) { chosen in
                addSuggestions(chosen, photo: target.index)
            }
        }
        .fullScreenCover(isPresented: $showZoom) { PhotoZoomView(room: room, photo: photoIndex, items: items) }
        .onChange(of: openCount) { old, new in
            if old > 0 && new == 0 && !relevant.isEmpty { showSummary = true }
        }
        .onChange(of: session.previewAsGuest) { cards = nil; skipped = [] }
    }

    private var cardTotal: Int {
        items.filter { SortRules.canDecide($0, as: me, in: room) || $0.askTo == me }.count
    }

    // MARK: List

    private var list: some View {
        // Grouped and ordered as of the last regroup; things added since go at the end of their group.
        let arr = arrangement ?? makeArrangement()
        let ordered = items.enumerated().sorted { a, b in
            let ka = arr.order[a.element.id] ?? Int.max, kb = arr.order[b.element.id] ?? Int.max
            return ka != kb ? ka < kb : a.offset < b.offset
        }.map(\.element)
        let sets = Dictionary(grouping: ordered) { arr.bucket[$0.id] ?? liveBucket($0) }
        let matching = (sets[view] ?? []).filter { item in
            arr.order[item.id] == nil ? filter.passes(item, me: me) : arr.passes.contains(item.id)
        }
        let shown = matching.filter { !isHidden($0) }
        let numbers = pinNumbers

        // A List (not a ScrollView) so rows get the system's swipe actions. Everything above the
        // things is one plain row; the things are an inset group, like the rest of the app.
        return ScrollViewReader { proxy in
            List {
                Section {
                    listHeader(sets: sets, matching: matching.count, numbers: numbers)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    if shown.isEmpty {
                        Text(emptyText)
                            .textRole(.secondary)
                            .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
                            .listRowInsets(EdgeInsets(top: 0, leading: Space.l, bottom: 0, trailing: Space.l))
                            .listRowBackground(Color.surface)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                        // No .id(): the ForEach's own identity (item.id) is what scrollTo finds.
                        let next = index + 1 < shown.count ? shown[index + 1].id : nil
                        row(item, number: numbers[item.id], next: next)
                        if canChoose && !selecting && isExpanded(item.id) {
                            choicesRow(item, next: next)
                        }
                    }
                }
                if context.canEditRoom && !selecting {
                    Section {
                        Button { session.addItem = AddItemRequest() } label: { Label("Add something", systemImage: "plus") }
                            .buttonStyle(.app(.primary, size: .compact))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(Space.m)
            .contentMargins(.horizontal, Space.page, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 0)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.viewport = $0 }
            .onScrollPhaseChange { _, phase in
                if phase == .idle { hideScrolledAway() }
            }
            .refreshable {
                await sync.refresh()
                regroup()
            }
            .onChange(of: selectedId) { _, id in
                if let id { withMotion(reduceMotion: reduceMotion) { proxy.scrollTo(id, anchor: .center) } }
            }
            .onChange(of: view) { regroup(); expanded = []; collapsed = [] }
            .onChange(of: filter) { regroup() }
        }
        // Back on Sort (from another tab or the cards): group things by where they are now.
        .onAppear {
            regroup()
            sync.lastDecision = nil
        }
        .onChange(of: sync.lastDecision) { _, record in
            // Wait for the item sheet to close, so the banner and highlight are seen.
            if let record, detailItem == nil { decided(record) }
        }
        .onChange(of: detailItem?.id) { _, now in
            if now == nil, let record = sync.lastDecision { decided(record) }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                Button {
                    for item in items where selectedIds.contains(item.id) && !item.isDecided {
                        SortActions.ask(about: item, as: me, sync: sync)
                    }
                    let n = selectedIds.count
                    selecting = false
                    selectedIds = []
                    sync.activity = ActivityEvent(text: "Asked \(room.name(of: me.other)) about \(n)", symbol: "text.bubble", status: nil)
                } label: {
                    Label("Ask \(room.name(of: me.other)) about \(selectedIds.isEmpty ? "" : "\(selectedIds.count)")", systemImage: "text.bubble")
                }
                .buttonStyle(.app)
                .disabled(selectedIds.isEmpty)
                .padding(.horizontal, Space.page).padding(.vertical, Space.s)
                .barBackground()
            }
        }
        .undoBanner($justDeleted, text: "Item deleted", calm: true) { item in
            SortActions.restore(item, sync: sync)
        }
        .undoBanner($decisionBanner, text: decisionBanner?.text ?? "", calm: true) { record in
            guard let item = items.first(where: { $0.id == record.itemId }) else { return }
            withMotion(Motion.subtleFade, reduceMotion: reduceMotion) { SortActions.undo(record, for: item, sync: sync) }
        }
    }

    /// Everything above the things: photos, the photo or 3D view, the tabs and the filter row.
    private func listHeader(sets: [Bucket: [Item]], matching: Int, numbers: [UUID: Int]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if !photos.isEmpty { photoBar }
            AdaptiveStack {
                Text(selecting ? "\(selectedIds.count) selected" : "\(items.count) thing\(items.count == 1 ? "" : "s")")
                    .textRole(.secondary)
                Spacer()
                if context.canEditRoom && room.hasGuest {
                    Button(selecting ? "Cancel" : "Select") { selecting.toggle(); selectedIds = [] }
                        .buttonStyle(.app(.primary, size: .compact))
                        .fixedSize()
                }
                ChipPicker(options: [.init(value: Stage.photo, title: "Photo"), .init(value: Stage.model, title: "3D view")],
                           selection: $stage, accessibilityLabel: "Show")
                    .fixedSize(horizontal: true, vertical: false)
            }
            stageView(numbers: numbers)
            if context.canEditRoom && stage == .photo && !photos.isEmpty && items.contains(where: \.hasPin) {
                Text("If a number is on the wrong thing, drag it onto the right one.")
                    .textRole(.hint)
            }
            if context.canEditRoom && stage == .photo && !photos.isEmpty { findThings }

            progress

            ChipPicker(options: [
                .init(value: Bucket.needs, title: "For you to decide", count: sets[.needs]?.count),
                .init(value: Bucket.waiting, title: room.hasGuest ? "Waiting for \(room.name(of: me.other))" : "Waiting for a decision",
                      count: sets[.waiting]?.count),
                .init(value: Bucket.decided, title: "Decided", count: sets[.decided]?.count),
            ], selection: $view, accessibilityLabel: "Items")

            AdaptiveStack {
                Text("\(matching) of \(sets[view]?.count ?? 0)\(filter.isActive ? " · filtered" : "")")
                    .textRole(.secondary)
                Spacer()
                if canChoose && !selecting {
                    Button { toggleExpandAll() } label: {
                        Label(expandAll ? "Collapse all" : "Expand all",
                              systemImage: expandAll ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                            // The new label appears at once; only the rows animate.
                            .transaction { $0.animation = nil }
                    }
                    .buttonStyle(.app(.neutral, size: .compact, width: .hug))
                    .lineLimit(1)
                    .layoutPriority(1)
                    .accessibilityLabel(expandAll ? "Collapse all items" : "Expand all items")
                }
                Button { showFilter = true } label: {
                    Label(filter.isActive ? "Filter · on" : "Filter", systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(.app(.primary, size: .compact, width: .hug))
                .lineLimit(1)
                .layoutPriority(1)
            }
        }
        .padding(.vertical, Space.m)
        // Inside the list, so it can find the list's scroll view (to hold rows still).
        .background { ScrollViewFinder { frames.scrollView = $0 } }
    }

    /// "7 of 11 decided", live, with "Hide decided". Counts change; the list below doesn't move.
    private var progress: some View {
        let counts = SortProgress(relevant)
        return VStack(alignment: .leading, spacing: Space.s) {
            AdaptiveStack {
                Text("\(counts.decided) of \(counts.total) decided")
                    .font(.bodyStrong).foregroundStyle(Color.textPrimary)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : Motion.subtleFade, value: counts.decided)
                Spacer()
                if view != .decided && !selecting {
                    Toggle("Hide decided", isOn: Binding(get: { session.hideDecidedItems }, set: setHideDecided))
                        .toggleStyle(.app)
                        .font(.bodyStrong).foregroundStyle(Color.textPrimary)
                        .fixedSize()
                        .frame(minHeight: Size.tapTarget)
                }
            }
            ProgressBar(value: counts.total > 0 ? Double(counts.decided) / Double(counts.total) : 0)
                .accessibilityLabel("Decided")
                .accessibilityValue("\(counts.decided) of \(counts.total)")
        }
    }

    private var emptyText: String {
        if session.hideDecidedItems && view != .decided && (arrangement?.bucket.values.contains(view) ?? false) {
            return "Decided things are hidden"
        }
        if filter.isActive { return "Nothing matches these filters" }
        switch view {
        case .needs: return "Nothing needs you right now"
        case .waiting: return room.hasGuest ? "Nothing waiting on \(room.name(of: me.other))" : "Nothing waiting"
        case .decided: return "Nothing decided yet"
        }
    }

    // MARK: Rows

    /// Decisions (or suggestions) can be made from the list; not while previewing a joined guest.
    private var canChoose: Bool { !context.readOnly }
    private var expandAll: Bool { session.expandAllItems }

    private func isExpanded(_ id: UUID) -> Bool {
        expandAll ? !collapsed.contains(id) : expanded.contains(id)
    }

    /// One thing: tap the name or photo for its sheet; the chevron opens the decision buttons in place.
    private func row(_ item: Item, number: Int?, next: UUID?) -> some View {
        let open = canChoose && !selecting && isExpanded(item.id)
        let canDelete = !selecting && SortActions.canRemove(item, context: context)
        return HStack(spacing: 0) {
                Button {
                    if selecting {
                        if selectedIds.contains(item.id) { selectedIds.remove(item.id) } else { selectedIds.insert(item.id) }
                    } else {
                        selectedId = item.id
                        detailItem = item
                    }
                } label: {
                    ItemRow(item: item, room: room, me: me, number: number,
                            selection: selecting ? selectedIds.contains(item.id) : nil,
                            showsChevron: !canChoose)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(selecting && item.isDecided)
                .accessibilityHint(selecting ? "" : "Opens notes, details and owner")
                .accessibilityActions {
                    if canDelete { Button("Delete", role: .destructive) { delete(item) } }
                }
                if canChoose && !selecting {
                    Button { toggle(item.id, next: next) } label: {
                        Image(systemName: "chevron.down")
                            .font(.detailStrong)
                            .foregroundStyle(Color.iconNeutral)
                            .rotationEffect(.degrees(open ? 180 : 0))
                            .frame(width: Size.tapTarget, height: Size.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(open ? "Hide choices for \(item.name)" : "Show choices for \(item.name)")
                }
        }
        .padding(.leading, Space.l)
        .padding(.trailing, Space.s)
        .opacity(fading.contains(item.id) ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.rows[item.id] = $0 }
        .background(alignment: .topLeading) { RowMarker(id: item.id, frames: frames).frame(width: 1, height: 1) }
        .onDisappear { frames.rows[item.id] = nil }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Group { if selectedId == item.id && !selecting { Tone.sage.fill } else { Color.surface } })
        .listRowSeparatorTint(Color.outline)
        // Its decision buttons are the next row, part of the same block.
        .listRowSeparator(open ? .hidden : .automatic, edges: .bottom)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if canDelete {
                Button(role: .destructive) { delete(item) } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .contextMenu {
            if !selecting && canChoose {
                let can = SortRules.canDecide(item, as: me, in: room)
                ForEach(can ? ItemStatus.decisions : ItemStatus.suggestions, id: \.self) { status in
                    Button(can ? status.shortLabel : "Suggest: \(status.shortLabel)", systemImage: status.icon) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withMotion(Motion.subtleFade, reduceMotion: reduceMotion) {
                            SortActions.choose(status, for: item, as: me, in: room, sync: sync)
                        }
                    }
                }
            }
            if canDelete {
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
            }
        }
    }

    /// An open row's decision buttons, as their own list row right under it. Opening a row inserts
    /// this row, which the list animates natively: it fades in and the rows below slide down,
    /// while the thing's own row never changes size.
    private func choicesRow(_ item: Item, next: UUID?) -> some View {
        choices(item, next: next)
            .padding(.leading, Space.l)
            .padding(.trailing, Space.s)
            .padding(.bottom, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(fading.contains(item.id) ? 0 : 1)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Group { if selectedId == item.id && !selecting { Tone.sage.fill } else { Color.surface } })
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparatorTint(Color.outline)
    }

    /// The five decisions (or "Suggest" versions when it's the other person's thing), in place.
    private func choices(_ item: Item, next: UUID?) -> some View {
        let deciding = SortRules.canDecide(item, as: me, in: room)
        let owner = item.owner.role.map { room.name(of: $0) } ?? room.name(of: me.other)
        return VStack(alignment: .leading, spacing: Space.s) {
            Text(deciding ? "Your decision" : "Suggest to \(owner)").textRole(.label)
            // Choosing changes only the button and the row's tag: the row stays open, in place.
            DecisionButtons(item: item, room: room, me: me)
            if !deciding {
                Text("It’s \(owner)’s to decide. They’ll see your suggestion.").textRole(.hint)
            }
        }
        .padding(.trailing, Space.s)
    }

    /// Opens or closes one row with a gentle height change. Nothing above it changes, so the row
    /// tapped stays where it is and only the rows below it move.
    private func toggle(_ id: UUID, next: UUID?) {
        let closing = isExpanded(id)
        withMotion(Motion.subtle, reduceMotion: reduceMotion) {
            if expandAll {
                if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
            } else {
                if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
            }
        }
        // Hide decided: closing a decided row, or opening another, is moving on.
        if closing {
            if pendingHide.contains(id) { hide([id], keeping: next) }
        } else {
            hide(pendingHide.subtracting([id]), keeping: id)
        }
    }

    /// Every row opens (or closes) together, in one short animation. The button is above every
    /// row, so no row above the screen changes size and the rows on screen stay where they are.
    private func toggleExpandAll() {
        withMotion(Motion.subtle, reduceMotion: reduceMotion) {
            session.expandAllItems.toggle()
            expanded = []
            collapsed = []
        }
    }

    /// Any decision made on this phone (list, long-press menu or item sheet): highlight, Undo banner,
    /// and, with "Hide decided" on, the previous decided rows go now that the person has moved on.
    private func decided(_ record: DecisionUndo) {
        sync.lastDecision = nil
        justDeleted = nil
        decisionBanner = record
        if session.hideDecidedItems {
            hide(pendingHide.subtracting([record.itemId]), keeping: record.itemId)
            pendingHide.insert(record.itemId)
        }
    }

    private func delete(_ item: Item) {
        withMotion(Motion.subtle, reduceMotion: reduceMotion) {
            SortActions.remove(item, sync: sync)
        }
        expanded.remove(item.id)
        collapsed.remove(item.id)
        pendingHide.remove(item.id)
        if selectedId == item.id { selectedId = nil }
        decisionBanner = nil
        justDeleted = item
    }

    // MARK: Stable list

    private func liveBucket(_ item: Item) -> Bucket {
        switch SortRules.rank(item, me: me, in: room) {
        case ...1: .needs
        case 2: .waiting
        default: .decided
        }
    }

    private func makeArrangement() -> Arrangement {
        let ranked = items.enumerated().sorted { a, b in
            let ra = SortRules.rank(a.element, me: me, in: room), rb = SortRules.rank(b.element, me: me, in: room)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        var arr = Arrangement()
        for (i, item) in ranked.enumerated() {
            arr.order[item.id] = i
            arr.bucket[item.id] = liveBucket(item)
            if filter.passes(item, me: me) { arr.passes.insert(item.id) }
        }
        return arr
    }

    /// Puts things in their groups as they are now. Only on a tab, filter or Sort change, or a pull.
    private func regroup() {
        arrangement = makeArrangement()
        pendingHide = []
        movedOn = []
        fading = []
    }

    private func isHidden(_ item: Item) -> Bool {
        session.hideDecidedItems && view != .decided && item.isDecided && movedOn.contains(item.id)
    }

    private func setHideDecided(_ on: Bool) {
        let first = firstVisibleRow(excluding: [])
        if on {
            // Turned on by hand: what's already decided goes now, the rows on screen stay put.
            let decided = Set(items.filter(\.isDecided).map(\.id))
            keepInPlace(first.flatMap { decided.contains($0) ? nil : $0 }) {
                session.hideDecidedItems = true
                movedOn.formUnion(decided)
            }
        } else {
            keepInPlace(first) {
                session.hideDecidedItems = false
                movedOn = []
                pendingHide = []
            }
        }
    }

    /// Fades decided rows out, then takes them out of the list without moving `keeping` on screen.
    private func hide(_ ids: Set<UUID>, keeping anchor: UUID?) {
        guard !ids.isEmpty else { return }
        pendingHide.subtract(ids)
        withMotion(Motion.subtle, reduceMotion: reduceMotion) { fading.formUnion(ids) }
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(220)) }
            keepInPlace(anchor ?? firstVisibleRow(excluding: ids)) {
                movedOn.formUnion(ids)
                fading.subtract(ids)
            }
        }
    }

    /// Hide decided: rows decided here and then scrolled off screen go once scrolling stops.
    private func hideScrolledAway() {
        let gone = pendingHide.filter { !frames.isVisible($0) }
        guard !gone.isEmpty else { return }
        pendingHide.subtract(gone)
        keepInPlace(firstVisibleRow(excluding: gone)) { movedOn.formUnion(gone) }
    }

    private func firstVisibleRow(excluding: Set<UUID>) -> UUID? {
        frames.rows.filter { !excluding.contains($0.key) && $0.value.minY >= frames.viewport.minY && frames.isVisible($0.key) }
            .min { $0.value.minY < $1.value.minY }?.key
    }

    /// Makes a change to the list without the row `anchor` moving on screen: the list scrolls by
    /// however far the change would have moved it, in the same frame.
    private func keepInPlace(_ anchor: UUID?, _ change: () -> Void) {
        if let anchor { frames.hold(anchor) }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, change)
    }

    // MARK: Photo and plan

    /// Items with a pin get a number, in list order; the same number is on the photo and the row.
    private var pinNumbers: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: items.filter(\.hasPin).enumerated().map { ($1.id, $0 + 1) })
    }

    /// "Find things in this photo": optional, on-device suggestions for the photo on screen.
    private var findThings: some View {
        let shown = photos.contains(photoIndex) ? photoIndex : (photos.first ?? 0)
        return VStack(alignment: .leading, spacing: Space.xs) {
            Button {
                if let image = RoomPhotos.image(roomId: room.id, index: shown, revision: sync.photoRevision) {
                    findIn = PhotoToSearch(index: shown, image: image)
                }
            } label: {
                Label("Find things in this photo", systemImage: "sparkle.magnifyingglass")
            }
            .buttonStyle(.app(.neutral, size: .compact, width: .hug))
            .accessibilityHint("Suggests things to add. You check each one first.")
            Text(DetectionReviewSheet.privacyNote).textRole(.hint)
        }
    }

    private func existingThings(on photo: Int) -> [ExistingThing] {
        items.map {
            ExistingThing(id: $0.id, name: $0.name, category: $0.category, pin: $0.pin(on: photo),
                          scanned: $0.source == .scanned, pinnedAnywhere: $0.hasPin)
        }
    }

    /// Confirmed suggestions: a scanned match gets its number on the photo; anything else is added.
    private func addSuggestions(_ chosen: [DetectionSuggestion], photo: Int) {
        guard !chosen.isEmpty else { return }
        var all = Array(items)
        let owner = SortActions.defaultOwner(in: room, items: all)
        var added = 0, linked = 0
        for s in chosen {
            if let match = s.match, let item = all.first(where: { $0.id == match.id }) {
                if item.name != s.name { item.name = s.name }
                SortActions.setPin(s.pin, photo: photo, for: item, sync: sync)
                linked += 1
            } else {
                all.append(SortActions.addItem(name: s.name, category: s.category, owner: owner, pin: s.pin, photo: photo,
                                               to: room, existing: all, sync: sync))
                added += 1
            }
        }
        photoIndex = photo
        let parts = [added > 0 ? "Added \(added) \(added == 1 ? "thing" : "things")" : nil,
                     linked > 0 ? "numbered \(linked) from your scan" : nil].compactMap { $0 }
        let text = parts.joined(separator: ", ")
        sync.activity = ActivityEvent(text: text.prefix(1).uppercased() + text.dropFirst(), symbol: "checkmark", status: nil)
    }

    private var photoBar: some View {
        AdaptiveStack(spacing: Space.m) {
            if photos.count > 1 {
                ChipPicker(options: photos.map { .init(value: $0, title: "Photo \($0 + 1)") },
                           selection: Binding(get: { photoIndex }, set: { photoIndex = $0; selectedId = nil }),
                           accessibilityLabel: "Photos")
            }
            Spacer(minLength: 0)
            if context.canEditRoom && room.photoCount < Room.maxPhotos {
                AddPhotoMenu(title: "Another angle") { image in
                    let index = room.photoCount
                    guard let jpeg = image.jpegForUpload(), sync.savePhoto(jpeg, index: index, of: room) else { return }
                    photoIndex = index
                    stage = .photo
                    sync.activity = ActivityEvent(text: "Tap anything the first photo missed to add it", symbol: "plus", status: nil)
                }
            }
            IconButton(symbol: "plus.magnifyingglass", label: "Zoom in on the photo", filled: true) { showZoom = true }
                .disabled(photos.isEmpty)
        }
    }

    @ViewBuilder private func stageView(numbers: [UUID: Int]) -> some View {
        Group {
            if stage == .model {
                RoomModelView(room: room, entries: DesignResolver.resolve(items: items, design: nil, room: room).entries,
                              selectedId: selectedId) { id in selectedId = id }
                    .aspectRatio(4 / 3, contentMode: .fit)
            } else if let image = RoomPhotos.image(roomId: room.id, index: photos.contains(photoIndex) ? photoIndex : (photos.first ?? 0),
                                                   revision: sync.photoRevision) {
                let shownPhoto = photos.contains(photoIndex) ? photoIndex : (photos.first ?? 0)
                PhotoWithPins(
                    image: image,
                    pins: items.compactMap { item in
                        item.pin(on: shownPhoto).map {
                            PhotoPin(id: item.id, number: numbers[item.id] ?? 0, label: item.name, point: $0,
                                     status: item.status, statusText: SortRules.spokenStatus(item, room: room),
                                     isSelected: item.id == selectedId)
                        }
                    },
                    onTapPin: { id in selectedId = selectedId == id ? nil : id },
                    onTapPhoto: context.canEditRoom && !selecting ? { point in
                        session.addItem = AddItemRequest(pin: point, photo: shownPhoto)
                    } : nil,
                    onMovePin: context.canEditRoom ? { id, point in
                        if let item = items.first(where: { $0.id == id }) {
                            SortActions.setPin(point, photo: shownPhoto, for: item, sync: sync)
                        }
                    } : nil)
            } else {
                noPhoto
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.stage)
        .clipShape(RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
    }

    @ViewBuilder private var noPhoto: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "photo").font(.glyph(.large)).foregroundStyle(Color.textSecondary).accessibilityHidden(true)
            Text(context.canEditRoom ? "Add a photo of the room to number the things in it." : "No photo yet")
                .textRole(.secondary).multilineTextAlignment(.center)
            if context.canEditRoom {
                AddPhotoMenu(title: "Add a photo") { image in
                    if let jpeg = image.jpegForUpload() { sync.savePhoto(jpeg, index: 0, of: room); photoIndex = 0 }
                }
                .buttonStyle(.app(.neutral, size: .compact, width: .hug))
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, minHeight: Size.previewImageMax)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                NoItemsYetView(context: context,
                               message: "Take a photo of the room and tap each thing in it, or add things by hand. Then decide what stays, what goes back to its owner, and what you donate or throw out.") {
                    session.addItem = AddItemRequest()
                }
                if context.canEditRoom && DeviceCapabilities.canScanRooms {
                    Button { consent { session.showScan = true } } label: {
                        ChoiceTile(title: "Scan with LiDAR",
                                   detail: "Measures the walls, doors and windows. \(ScanCopy.before)",
                                   symbol: "viewfinder")
                    }
                    .buttonStyle(.plain)
                }
                if context.canEditRoom {
                    PhotoSourceButtons { image in
                        if let jpeg = image.jpegForUpload() { sync.savePhoto(jpeg, index: 0, of: room) }
                    }
                }
            }
            .padding(Space.page)
        }
    }
}

/// Owner and decision filters for the list.
struct ItemFilter: Equatable {
    enum OwnerFilter: Hashable { case any, mine, theirs, both }
    var owner: OwnerFilter = .any
    var decision: ItemStatus?

    var isActive: Bool { owner != .any || decision != nil }

    func passes(_ item: Item, me: Role) -> Bool {
        let ownerOK: Bool = switch owner {
        case .any: true
        case .mine: item.owner == Owner(me)
        case .theirs: item.owner == Owner(me.other)
        case .both: item.owner == .shared
        }
        return ownerOK && (decision == nil || item.status == decision)
    }
}

struct FilterSheet: View {
    let room: Room
    let me: Role
    @Binding var filter: ItemFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Owner")
                        PickRow(title: "Anyone", isSelected: filter.owner == .any) { filter.owner = .any }
                        PickRow(title: "Me", isSelected: filter.owner == .mine) { filter.owner = .mine }
                        if room.hasGuest {
                            PickRow(title: room.name(of: me.other), isSelected: filter.owner == .theirs) { filter.owner = .theirs }
                            PickRow(title: "Both", isSelected: filter.owner == .both) { filter.owner = .both }
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Decision")
                        PickRow(title: "Any decision", isSelected: filter.decision == nil) { filter.decision = nil }
                        ForEach(ItemStatus.decisions, id: \.self) { status in
                            PickRow(title: status.shortLabel, isSelected: filter.decision == status) { filter.decision = status }
                        }
                    }
                    Button("Show items") { dismiss() }.buttonStyle(.app)
                    Button("Clear filters") { filter = ItemFilter() }.buttonStyle(.app(.neutral, size: .compact))
                        .frame(maxWidth: .infinity)
                }
                .padding(Space.page)
            }
            .appSheet()
            .appNavigation("Filter items")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// "Another angle": take a photo or pick one, as a menu.
struct AddPhotoMenu: View {
    let title: String
    var onPick: (UIImage) -> Void
    @Environment(\.captureConsent) private var consent
    @State private var showCamera = false
    @State private var showLibrary = false

    var body: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button("Take a photo", systemImage: "camera") { consent { showCamera = true } }
            }
            Button("Choose from library", systemImage: "photo.on.rectangle") { consent { showLibrary = true } }
        } label: {
            Label(title, systemImage: "camera")
        }
        .menuStyle(.button)
        .buttonStyle(.app(.primary, size: .compact))
        .photoLibraryImport(isPresented: $showLibrary, onPick: onPick)
        .fullScreenCover(isPresented: $showCamera) { CameraPicker(onPick: onPick).ignoresSafeArea() }
    }
}

/// The photo, large, with pinch to zoom.
struct PhotoZoomView: View {
    let room: Room
    let photo: Int
    let items: [Item]
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    if let image = RoomPhotos.image(roomId: room.id, index: photo, revision: sync.photoRevision) {
                        let numbers = Dictionary(uniqueKeysWithValues: items.filter(\.hasPin).enumerated().map { ($1.id, $0 + 1) })
                        PhotoWithPins(image: image, pins: items.compactMap { item in
                            item.pin(on: photo).map {
                                PhotoPin(id: item.id, number: numbers[item.id] ?? 0, label: item.name, point: $0,
                                         status: item.status, statusText: SortRules.spokenStatus(item, room: room))
                            }
                        })
                        .frame(width: geo.size.width * scale * pinch)
                    }
                }
            }
            .gesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in scale = min(max(scale * value.magnification, 1), 4) })
            .background(Color.stage)
            .appNavigation("Photo")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { scale = max(1, scale / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel("Zoom out")
                    Spacer()
                    Button { scale = min(4, scale * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel("Zoom in")
                }
            }
        }
    }
}

/// Where the list's rows are on screen, and the List's own scroll view. Not observed, so it
/// updates on every scroll frame without redrawing anything.
@MainActor
private final class RowFrames {
    var rows: [UUID: CGRect] = [:]
    var viewport: CGRect = .zero
    weak var scrollView: UIScrollView?
    /// A tiny UIKit view inside each row, to read where UIKit really has it (SwiftUI's reported
    /// positions lag behind while the list is updating).
    private var markers: [UUID: WeakView] = [:]
    private var held: (id: UUID, screenY: CGFloat, until: CFTimeInterval)?
    private var link: CADisplayLink?

    func isVisible(_ id: UUID) -> Bool {
        guard let frame = rows[id], frame.height > 0 else { return false }
        return frame.intersects(viewport)
    }

    func mark(_ id: UUID, _ view: UIView) { markers[id] = WeakView(view) }

    /// The row's top in the scroll view's content.
    private func contentY(_ id: UUID) -> CGFloat? {
        guard let scroll = scrollView, let view = markers[id]?.view, view.window != nil, view.isDescendant(of: scroll)
        else { return nil }
        return view.convert(CGPoint.zero, to: scroll).y
    }

    /// Keeps a row at the same height on screen while the list changes around it: for a moment,
    /// every frame, the list scrolls by however far the row has moved. Stops if the person scrolls.
    func hold(_ id: UUID) {
        guard let scroll = scrollView, let y = contentY(id) else { return }
        held = (id, y - scroll.contentOffset.y, CACurrentMediaTime() + 0.6)
        guard link == nil else { return }
        let link = CADisplayLink(target: LinkTarget { [weak self] in self?.tick() }, selector: #selector(LinkTarget.fire))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func tick() {
        guard let held, let scroll = scrollView, CACurrentMediaTime() < held.until,
              !scroll.isTracking, !scroll.isDecelerating else {
            link?.invalidate(); link = nil; self.held = nil
            return
        }
        guard let y = contentY(held.id) else { return }
        let top = -scroll.adjustedContentInset.top
        let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let target = min(max(y - held.screenY, top), bottom)
        if abs(scroll.contentOffset.y - target) > 0.5 { scroll.contentOffset.y = target }
    }
}

private struct WeakView {
    weak var view: UIView?
    init(_ view: UIView) { self.view = view }
}

/// CADisplayLink holds its target strongly; this keeps RowFrames out of that cycle.
private final class LinkTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

/// Registers a row's UIKit position marker.
private struct RowMarker: UIViewRepresentable {
    let id: UUID
    let frames: RowFrames

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { frames.mark(id, view) }
}

/// Finds the UIScrollView a SwiftUI List is drawn in.
private struct ScrollViewFinder: UIViewRepresentable {
    let found: (UIScrollView) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            var next = view?.superview
            while let candidate = next, !(candidate is UIScrollView) { next = candidate.superview }
            if let scroll = next as? UIScrollView { found(scroll) }
        }
    }
}
