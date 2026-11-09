import RoomPlan
import SwiftUI

/// Creating a room, in four short steps (two for an empty room):
/// room details → size → photos → check what's in it. Ends with "Create room" (and invite).
struct NewRoomFlow: View {
    /// Called with the new room, and whether to open the invite next.
    var onCreate: (Room, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync

    @State private var step = 0
    @State private var myName = Identity.name
    @State private var roomName = ""
    @State private var currentUse = ""
    @State private var futureUse = ""
    @State private var otherUse = false
    @State private var hasItems = true
    @State private var invite = false
    @State private var guestName = ""
    @State private var shape = RoomShape.rectangle(width: 340, length: 380)
    private var width: Double { shape.bounds.maxX }
    private var length: Double { shape.bounds.maxZ }
    @State private var height = 250.0
    @State private var measured = false
    @State private var photos: [UIImage] = []
    @State private var photoIndex = 0
    @State private var items: [Draft] = []
    @State private var editing: DraftEdit?
    @State private var problem: String?
    @State private var showScan = false
    @State private var captured: CapturedRoom?
    private let askName = Identity.name.isEmpty

    static let currentOptions = ["Bedroom", "Office", "Storage room", "Living room", "Spare room"]
    static let futureOptions = ["Study", "Guest room", "Bedroom", "Home office", "Home gym", "Still deciding"]
    static let presets: [(String, Double, Double)] = [
        ("Box room", 240, 280), ("Small bedroom", 300, 340), ("Double bedroom", 340, 380), ("Large room", 420, 460),
    ]
    private let units = UnitSystem.feet

    /// A thing listed before the room exists.
    struct Draft: Identifiable {
        let id = UUID()
        var name: String
        var owner: Owner
        var pin: CGPoint?
        var photo = 0
        /// Found by the LiDAR scan: real size and position.
        var scanned: ScanResult.Object?
    }

    struct DraftEdit: Identifiable {
        let id = UUID()
        var index: Int?
        var pin: CGPoint?
        var photo = 0
    }

    private var stepCount: Int { hasItems ? 4 : 2 }
    private let titles = ["Room details", "Room size", "Room photos", "Review items"]
    private let headings = ["Which room are we changing?", "How big is the room?", "Show the room as it is now", "Check what’s in the room"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    progress
                    Text(headings[step]).font(.screenTitle).accessibilityAddTraits(.isHeader)
                    switch step {
                    case 0: detailsStep
                    case 1: sizeStep
                    case 2: photosStep
                    default: reviewStep
                    }
                    if let problem {
                        Text(problem).font(.detailStrong).foregroundStyle(Color.letGo)
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.pageBackground)
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(titles[step])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == 0 {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button { withAnimation { step -= 1; problem = nil } } label: {
                            Label("Back", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(step + 1) of \(stepCount)").textRole(.secondary)
                        .accessibilityLabel("Step \(step + 1) of \(stepCount)")
                }
            }
            .fullScreenCover(isPresented: $showScan) {
                ScanFlowView { result, room in
                    shape = result.shape
                    height = result.heightCm
                    measured = true
                    captured = room
                    hasItems = hasItems || !result.objects.isEmpty
                    items.removeAll { $0.scanned != nil }
                    items += result.objects.map { Draft(name: $0.name, owner: invite ? .guest : .host, scanned: $0) }
                }
            }
            .sheet(item: $editing) { edit in
                DraftItemSheet(draft: edit.index.map { items[$0] }, guestName: invite ? guestName.trimmed : nil) { result in
                    if let i = edit.index {
                        if let result { items[i].name = result.name; items[i].owner = result.owner } else { items.remove(at: i) }
                    } else if let result {
                        items.append(Draft(name: result.name, owner: result.owner, pin: edit.pin, photo: edit.photo))
                    }
                }
            }
        }
    }

    // MARK: Steps

    private var progress: some View {
        ProgressSegments(count: stepCount, current: step)
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            if askName { field("Your name", text: $myName, placeholder: "Linda", content: .givenName) }
            field("Room name", text: $roomName, placeholder: "Alex’s old room")
            chips("Current use", options: Self.currentOptions, selection: $currentUse)
            VStack(alignment: .leading, spacing: Space.s) {
                chips("Planned use", options: Self.futureOptions + ["Other"],
                      selection: Binding(get: { otherUse ? "Other" : futureUse }, set: { value in
                          otherUse = value == "Other"
                          futureUse = otherUse ? "" : value
                      }))
                if otherUse { TextField("What will it become?", text: $futureUse).textFieldStyle(.app) }
            }
            VStack(alignment: .leading, spacing: Space.s) {
                SectionLabel("Are there items to sort?")
                PickRow(title: "Yes, there are items", isSelected: hasItems) { hasItems = true }
                PickRow(title: "No, the room is empty", isSelected: !hasItems) { hasItems = false }
            }
            VStack(alignment: .leading, spacing: Space.s) {
                SectionLabel("Who’s helping?")
                PickRow(title: "Just me", isSelected: !invite) { invite = false }
                PickRow(title: "Invite someone", isSelected: invite) { invite = true }
                if invite { field("Their first name", text: $guestName, placeholder: "Alex", content: .givenName) }
            }
        }
    }

    private var sizeStep: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if DeviceCapabilities.canScanRooms {
                Button { showScan = true } label: {
                    ChoiceTile(title: captured == nil ? "Scan with LiDAR" : "Scan again",
                               detail: captured == nil ? "Measures the walls, doors and windows and finds the furniture. Or draw it below."
                                                       : "Scanned. Adjust anything the scan got wrong below.",
                               symbol: "viewfinder")
                }
                .buttonStyle(.plain)
            }
            ShapeEditor(shape: $shape, units: units)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(Self.presets, id: \.0) { preset in
                        AppChip(title: preset.0, detail: "\(units.roomLength(preset.1)) × \(units.roomLength(preset.2))",
                                isSelected: width == preset.1 && length == preset.2) {
                            shape = shape.scaled(toWidth: preset.1, length: preset.2)
                            measured = false
                        }
                    }
                }
            }
            .scrollClipDisabled()
            LengthStepper(label: "Width", value: Binding(get: { width }, set: { shape = shape.scaled(toWidth: $0, length: length) }),
                          range: 150...2000, units: units)
            LengthStepper(label: "Length", value: Binding(get: { length }, set: { shape = shape.scaled(toWidth: width, length: $0) }),
                          range: 150...2000, units: units)
            LengthStepper(label: "Ceiling", value: $height, range: 200...400, units: units)
            PickRow(title: "I measured the room", subtitle: "Turns on fit checks in the room plan", isSelected: measured) { measured.toggle() }
        }
    }

    private var photosStep: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if !photos.isEmpty {
                Text("Take another angle if anything is hidden.").textRole(.secondary)
                gallery(withPins: false)
                Button("Remove this photo", role: .destructive) {
                    photos.remove(at: photoIndex)
                    items.removeAll { $0.photo == photoIndex }
                    photoIndex = max(0, min(photoIndex, photos.count - 1))
                }
                .buttonStyle(.link(.destructive))
            }
            if photos.count < Room.maxPhotos {
                PhotoSourceButtons(takeTitle: photos.isEmpty ? "Take a photo" : "Take another") { image in
                    photos.append(image)
                    photoIndex = photos.count - 1
                }
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if !photos.isEmpty {
                gallery(withPins: true)
                Text("Tap a thing in the photo to add it.").textRole(.secondary)
            } else {
                Text("Add the things in the room. You can add more later.").textRole(.secondary)
            }
            if !items.isEmpty {
                VStack(spacing: Space.xxs) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        Button { editing = DraftEdit(index: i) } label: {
                            HStack(spacing: Space.m) {
                                NumberBadge(number: i + 1, size: Size.tick)
                                VStack(alignment: .leading, spacing: Space.xxs) {
                                    Text(item.name).textRole(.bodyStrong)
                                    Text(ownerText(item.owner)).textRole(.secondary)
                                }
                                Spacer()
                                RowChevron()
                            }
                            .padding(.vertical, Space.m)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < items.count - 1 { Divider() }
                    }
                }
                .card(padding: Space.m)
            }
            Button { editing = DraftEdit() } label: { Label("Add an item", systemImage: "plus") }
                .buttonStyle(.link)
        }
    }

    private func gallery(withPins: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            let pins = withPins ? items.enumerated().compactMap { i, d in
                d.photo == photoIndex ? d.pin.map { PhotoPin(id: d.id, number: i + 1, label: d.name, point: $0) } : nil
            } : []
            PhotoWithPins(image: photos[photoIndex], pins: pins,
                          onTapPin: { id in editing = DraftEdit(index: items.firstIndex { $0.id == id }) },
                          onTapPhoto: withPins ? { point in editing = DraftEdit(pin: point, photo: photoIndex) } : nil,
                          onMovePin: withPins ? { id, point in
                              if let i = items.firstIndex(where: { $0.id == id }) { items[i].pin = point }
                          } : nil)
                .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            if photos.count > 1 {
                HStack(spacing: Space.s) {
                    ForEach(photos.indices, id: \.self) { i in
                        Button { photoIndex = i } label: {
                            Image(uiImage: photos[i]).resizable().scaledToFill()
                                .frame(width: Size.photoStrip.width, height: Size.photoStrip.height)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                                .padding(Space.xxs)
                                .overlay(RoundedRectangle(cornerRadius: Radius.s).strokeBorder(i == photoIndex ? Color.accent : .clear, lineWidth: Stroke.bold))
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: Size.row, minHeight: Size.control)
                        .accessibilityLabel("Photo \(i + 1)")
                        .accessibilityAddTraits(i == photoIndex ? .isSelected : [])
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Space.s) {
            Button(primaryTitle, action: next)
                .buttonStyle(.app(.primary))
                .disabled((step == 2 && photos.isEmpty) || (step == 1 && shape.selfIntersects))
            if step == 2 && photos.isEmpty {
                Button("Skip photos for now") { withAnimation { step += 1 } }
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(Color.pageBackground)
        .overlay(alignment: .top) { Divider() }
    }

    private var isLastStep: Bool { step == stepCount - 1 }

    private var primaryTitle: String {
        if !isLastStep { return ["Continue to room size", hasItems ? "Continue to room photos" : "", "Use these photos"][step] }
        return invite ? "Create room & invite \(guestName.trimmed)" : "Create room"
    }

    private func next() {
        problem = nil
        if step == 0 {
            if askName && myName.trimmed.isEmpty { problem = "Enter your name."; return }
            if roomName.trimmed.isEmpty { problem = "Give the room a name."; return }
            if invite && guestName.trimmed.isEmpty { problem = "Enter their first name."; return }
        }
        if isLastStep { create() } else { withAnimation { step += 1 } }
    }

    private func create() {
        if askName { Identity.name = myName }
        let guest = invite ? guestName.trimmed : ""
        let room = sync.createRoom(name: roomName.trimmed, currentUse: currentUse.isEmpty ? (hasItems ? "Room" : "Empty room") : currentUse,
                                   futureUse: futureUse.trimmed, hostName: Identity.name)
        room.shape = shape
        if let captured {
            room.scanVersion = 1
            ScanActions.save(captured, for: room.id)
        }
        room.heightCm = Int(height)
        room.measured = measured
        room.unitSystem = units
        if !guest.isEmpty { room.guestName = guest }
        sync.save(room)
        if hasItems {
            for (i, image) in photos.enumerated() {
                if let jpeg = image.jpegForUpload() { sync.savePhoto(jpeg, index: i, of: room) }
            }
            var added: [Item] = []
            for (i, draft) in items.enumerated() {
                if let o = draft.scanned {
                    let item = Item(room: room, name: draft.name, category: o.category, source: .scanned, size: (o.w, o.d, o.h),
                                    position: (o.x, 0, o.z), yawDeg: o.yawDeg, scanObjectId: o.id, sortOrder: i)
                    item.owner = draft.owner
                    if let pin = draft.pin { item.pinX = pin.x; item.pinY = pin.y; item.pinPhoto = draft.photo }
                    sync.insert(item)
                    sync.save(item)
                    added.append(item)
                } else {
                    let item = SortActions.addItem(name: draft.name, category: ItemCategory.guess(from: draft.name), owner: draft.owner,
                                                   pin: draft.pin, photo: draft.photo, to: room, existing: added, sync: sync)
                    added.append(item)
                }
            }
        }
        dismiss()
        onCreate(room, !guest.isEmpty)
    }

    // MARK: Helpers

    private func ownerText(_ owner: Owner) -> String {
        switch owner {
        case .guest: guestName.trimmed.isEmpty ? "Theirs" : guestName.trimmed
        case .shared: "Both"
        default: "Mine"
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, content: UITextContentType? = nil) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(label)
            TextField(placeholder, text: text)
                .textContentType(content)
                .textFieldStyle(.app)
                .accessibilityLabel(label)
        }
    }

    private func chips(_ label: String, options: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(label)
            FlowLayout {
                ForEach(options, id: \.self) { option in
                    AppChip(title: option, isSelected: selection.wrappedValue == option) {
                        selection.wrappedValue = selection.wrappedValue == option ? "" : option
                    }
                }
            }
        }
    }
}

/// Name and owner for a thing listed while creating a room.
private struct DraftItemSheet: View {
    let draft: NewRoomFlow.Draft?
    let guestName: String?
    /// nil = remove.
    var onDone: ((name: String, owner: Owner)?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var owner: Owner = .host

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    SectionLabel("Item name")
                    TextField("Sewing machine", text: $name).textFieldStyle(.app).submitLabel(.done)
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    SectionLabel("Owner")
                    PickRow(title: "Me", isSelected: owner == .host) { owner = .host }
                    if let guestName, !guestName.isEmpty {
                        PickRow(title: guestName, isSelected: owner == .guest) { owner = .guest }
                        PickRow(title: "Both", isSelected: owner == .shared) { owner = .shared }
                    }
                }
                Button("Save item") {
                    onDone((name.trimmed, owner))
                    dismiss()
                }
                .buttonStyle(.app)
                .disabled(name.trimmed.isEmpty)
                if draft != nil {
                    Button("Remove item", role: .destructive) { onDone(nil); dismiss() }
                        .buttonStyle(.link(.destructive))
                }
                Spacer()
            }
            .padding(Space.l)
            .background(Color.surface)
            .navigationTitle(draft == nil ? "Add an item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                name = draft?.name ?? ""
                owner = draft?.owner ?? (guestName?.isEmpty == false ? .guest : .host)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
