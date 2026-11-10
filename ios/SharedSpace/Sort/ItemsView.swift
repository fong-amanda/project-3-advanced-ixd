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

    enum Bucket: Hashable { case needs, waiting, decided }
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
                    withAnimation { cards = !showingCards }
                } label: {
                    ToolbarIcon(symbol: showingCards ? "list.bullet" : "rectangle.stack")
                }
                .accessibilityLabel(showingCards ? "Show as a list" : "One at a time")
            }
        }
        .sheet(item: $detailItem) { item in ItemDetailSheet(item: item, room: room) }
        .sheet(isPresented: $showFilter) { FilterSheet(room: room, me: me, filter: $filter) }
        .sheet(isPresented: $showSummary) {
            SortSummarySheet(items: relevant, room: room, me: me) { router.roomTab = .plan }
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
        let ordered = items.sorted { SortRules.rank($0, me: me, in: room) < SortRules.rank($1, me: me, in: room) }
        let sets: [Bucket: [Item]] = [
            .needs: ordered.filter { SortRules.rank($0, me: me, in: room) <= 1 },
            .waiting: ordered.filter { SortRules.rank($0, me: me, in: room) == 2 },
            .decided: ordered.filter { SortRules.rank($0, me: me, in: room) == 3 },
        ]
        let shown = (sets[view] ?? []).filter { filter.passes($0, me: me) }
        let numbers = pinNumbers

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    if !photos.isEmpty { photoBar }
                    HStack {
                        Text(selecting ? "\(selectedIds.count) selected" : "\(items.count) thing\(items.count == 1 ? "" : "s")")
                            .textRole(.secondary)
                        Spacer()
                        if context.canEditRoom && room.hasGuest {
                            Button(selecting ? "Cancel" : "Select") { selecting.toggle(); selectedIds = [] }
                                .buttonStyle(.app(.primary, size: .compact))
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

                    ChipPicker(options: [
                        .init(value: Bucket.needs, title: "For you to decide", count: sets[.needs]?.count),
                        .init(value: Bucket.waiting, title: room.hasGuest ? "Waiting for \(room.name(of: me.other))" : "Waiting for a decision",
                              count: sets[.waiting]?.count),
                        .init(value: Bucket.decided, title: "Decided", count: sets[.decided]?.count),
                    ], selection: $view, accessibilityLabel: "Items")

                    HStack {
                        Text("\(shown.count) of \(sets[view]?.count ?? 0)\(filter.isActive ? " · filtered" : "")")
                            .textRole(.secondary)
                        Spacer()
                        Button { showFilter = true } label: {
                            Label(filter.isActive ? "Filter · on" : "Filter", systemImage: "line.3.horizontal.decrease")
                        }
                        .buttonStyle(.app(.primary, size: .compact))
                    }

                    VStack(spacing: Space.xs) {
                        if shown.isEmpty {
                            Text(emptyText)
                                .textRole(.secondary)
                                .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
                                .padding(.horizontal, Space.l)
                        }
                        ForEach(shown) { item in
                            row(item, number: numbers[item.id])
                                .id(item.id)
                            if item.id != shown.last?.id { Hairline(inset: Space.l + Size.thumbnail + Space.m) }
                        }
                    }
                    .listGroup()

                    if context.canEditRoom && !selecting {
                        Button { session.addItem = AddItemRequest() } label: { Label("Add something", systemImage: "plus") }
                            .buttonStyle(.app(.primary, size: .compact))
                    }
                }
                .pagePadding()
            }
            .onChange(of: selectedId) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
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
    }

    private var emptyText: String {
        if filter.isActive { return "Nothing matches these filters" }
        switch view {
        case .needs: return "Nothing needs you right now"
        case .waiting: return room.hasGuest ? "Nothing waiting on \(room.name(of: me.other))" : "Nothing waiting"
        case .decided: return "Nothing decided yet"
        }
    }

    private func row(_ item: Item, number: Int?) -> some View {
        Button {
            if selecting {
                if selectedIds.contains(item.id) { selectedIds.remove(item.id) } else { selectedIds.insert(item.id) }
            } else {
                selectedId = item.id
                detailItem = item
            }
        } label: {
            ItemRow(item: item, room: room, me: me, number: number,
                    selection: selecting ? selectedIds.contains(item.id) : nil)
                .padding(.horizontal, Space.l)
                .background { if selectedId == item.id && !selecting { Tone.sage.fill } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selecting && item.isDecided)
        .contextMenu {
            if !selecting {
                let can = SortRules.canDecide(item, as: me, in: room)
                ForEach(can ? ItemStatus.decisions : ItemStatus.suggestions, id: \.self) { status in
                    Button(can ? status.shortLabel : "Suggest: \(status.shortLabel)", systemImage: status.icon) {
                        SortActions.choose(status, for: item, as: me, in: room, sync: sync)
                    }
                }
            }
        }
    }

    // MARK: Photo and plan

    /// Items with a pin get a number, in list order; the same number is on the photo and the row.
    private var pinNumbers: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: items.filter(\.hasPin).enumerated().map { ($1.id, $0 + 1) })
    }

    private var photoBar: some View {
        HStack(spacing: Space.m) {
            if photos.count > 1 {
                ChipPicker(options: photos.map { .init(value: $0, title: "Photo \($0 + 1)") },
                           selection: Binding(get: { photoIndex }, set: { photoIndex = $0; selectedId = nil }),
                           accessibilityLabel: "Photos")
            }
            Spacer(minLength: 0)
            if context.canEditRoom && room.photoCount < Room.maxPhotos {
                AddPhotoMenu(title: "Another angle") { image in
                    guard let jpeg = image.jpegForUpload() else { return }
                    let index = room.photoCount
                    sync.savePhoto(jpeg, index: index, of: room)
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
                                     status: item.status, isSelected: item.id == selectedId)
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
                    Button { session.showScan = true } label: {
                        ChoiceTile(title: "Scan with LiDAR", detail: "Measures the walls, doors and windows and finds the furniture",
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
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var item: PhotosPickerItem?

    var body: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button("Take a photo", systemImage: "camera") { showCamera = true }
            }
            Button("Choose from library", systemImage: "photo.on.rectangle") { showLibrary = true }
        } label: {
            Label(title, systemImage: "camera")
        }
        .menuStyle(.button)
        .buttonStyle(.app(.primary, size: .compact))
        .photosPicker(isPresented: $showLibrary, selection: $item, matching: .images)
        .fullScreenCover(isPresented: $showCamera) { CameraPicker(onPick: onPick).ignoresSafeArea() }
        .onChange(of: item) { _, new in
            guard let new else { return }
            Task {
                if let data = try? await new.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    onPick(image.normalisedUp())
                }
                item = nil
            }
        }
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
                            item.pin(on: photo).map { PhotoPin(id: item.id, number: numbers[item.id] ?? 0, label: item.name, point: $0, status: item.status) }
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
