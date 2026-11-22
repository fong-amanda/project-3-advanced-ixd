import SwiftData
import SwiftUI

/// Room plan tab. Starts with the room as it is now (no sorting needed); things Sort sends out are
/// hidden. The host places furniture in "Proposed layout", saves versions and shares one; the guest
/// looks and reacts with "Looks good" or "One thing…".
struct RoomPlanView: View {
    let room: Room
    @Environment(SyncEngine.self) private var sync
    @Environment(RoomSession.self) private var session
    @Environment(\.captureConsent) private var consent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var items: [Item]
    @Query private var designs: [Design]

    @State private var selectedPiece: UUID?
    @State private var category: CatalogPiece.Category = .all
    @State private var fitMode: FitMode = .any
    @State private var customSpace = FitSpace(w: 120, d: 200, h: 250)
    @State private var showNoFit = false
    @State private var showFit = false
    @State private var detailPiece: CatalogPiece?
    @State private var showCustom = false
    @State private var showPreview = false
    @State private var showReactNote = false
    @State private var showHidden = false
    @State private var showShape = false
    /// "View in your room": the live AR view, and the piece chosen when it opens.
    @State private var showAR = false
    @State private var arInitialPiece: CatalogPiece?
    @State private var planView: PlanViewMode = .floorPlan
    /// The piece just added from the catalogue: highlighted, and offered for Undo in the banner.
    @State private var justPlaced: JustPlaced?
    @State private var highlight: JustPlaced?

    struct JustPlaced: Identifiable, Equatable {
        let id = UUID()
        let placementId: UUID
        let name: String
        let fits: Bool
        let at = Date()
    }

    enum PlanViewMode: Hashable { case floorPlan, model }

    enum FitMode: Hashable { case any, zone(Int), custom }

    init(room: Room) {
        self.room = room
        _items = Query(Item.live(in: room.id))
        _designs = Query(Design.live(in: room.id))
    }

    private var context: RoomContext { session.context(room, userId: sync.userId) }
    private var isHost: Bool { context.canEditRoom }
    private var units: UnitSystem { room.unitSystem }
    private var sharedDesign: Design? { designs.first { $0.id == room.sharedDesignId } }

    /// The version on screen. Host: the working plan by default. Guest: the shared one.
    private var design: Design? {
        if session.planDesignPicked { return designs.first { $0.id == session.planDesignId } }
        if isHost { return designs.first { !$0.locked } ?? designs.first }
        return sharedDesign ?? designs.first
    }
    private var canEditDesign: Bool { isHost && !(design?.locked ?? false) }
    private var resolved: ResolvedDesign { DesignResolver.resolve(items: items, design: design, room: room) }
    private var zones: [FreeZone] { isHost ? FreeZones.compute(items: items, room: room) : [] }

    var body: some View {
        let resolved = resolved
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header(resolved)
                versions
                ChipPicker(options: [.init(value: PlanViewMode.floorPlan, title: "Floor plan"),
                                            .init(value: PlanViewMode.model, title: "3D")], selection: $planView)
                    .id(Self.roomViewAnchor)
                if planView == .model {
                    RoomModelView(room: room, entries: resolved.entries, showGhosts: showHidden || design == nil,
                                  selectedId: selectedPiece, onSelect: { id in selectedPiece = id },
                                  movableIds: canEditDesign ? Set(resolved.pieces.map(\.placement.id)) : [],
                                  onMovePiece: canEditDesign ? { id, x, z, yaw in
                                      if let p = resolved.pieces.first(where: { $0.placement.id == id })?.placement {
                                          DesignActions.place(p, x: x, z: z, yawDeg: yaw, sync: sync)
                                      }
                                  } : nil,
                                  highlightId: highlight?.placementId)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
                    if canEditDesign && !resolved.pieces.isEmpty {
                        Text("Drag a piece to move it, twist with two fingers to turn it. Drag the floor to look around; pinch to zoom.")
                            .textRole(.hint)
                    }
                } else {
                    plan(resolved)
                }
                if let entry = resolved.entries.first(where: { $0.id == selectedPiece && $0.style == .newPiece }),
                   let p = resolved.pieces.first(where: { $0.placement.id == entry.id }), canEditDesign {
                    pieceBar(entry, placement: p.placement, piece: p.piece)
                }
                notes(resolved)
                reaction
                if isHost {
                    if design?.locked == true {
                        Button("Continue from this version") {
                            if let design {
                                let working = DesignActions.continueFrom(design, room: room, existing: designs, sync: sync)
                                pick(working)
                                sync.activity = ActivityEvent(text: "Continuing from \(design.name)", symbol: "doc.on.doc", status: nil)
                            }
                        }
                        .buttonStyle(.app(.neutral))
                    } else {
                        catalogue { piece in place(piece, proxy: proxy) }
                    }
                } else {
                    pieceList(resolved)
                }
            }
            .pagePadding()
        }
        }
        .pageBackground()
        .undoBanner($justPlaced, text: justPlaced.map { $0.fits ? "Added \($0.name). Drag it to move it." :
                                                     "Added \($0.name), but there’s no free space where it fits. Drag it somewhere or remove it." } ?? "") { added in
            if let p = designs.flatMap(\.livePlacements).first(where: { $0.id == added.placementId }) {
                DesignActions.remove(p, sync: sync)
                if selectedPiece == added.placementId { selectedPiece = nil }
                highlight = nil
            }
        }
        .roomChrome(room)
        .sheet(isPresented: $showShape) { ShapeEditorSheet(room: room) }
        #if DEBUG
        .onAppear { if DemoData.show3D { planView = .model } }
        #endif
        .sheet(item: $detailPiece) { piece in
            PieceDetailSheet(piece: piece, units: units) {
                // Close the sheet, then open AR with this piece chosen.
                detailPiece = nil
                arInitialPiece = piece
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showAR = true }
            }
        }
        .fullScreenCover(isPresented: $showAR, onDismiss: { arInitialPiece = nil }) {
            arView(resolved)
        }
        .sheet(isPresented: $showCustom) {
            CustomPieceSheet(units: units) { name, w, d, h in
                let piece = Catalogue.piece(Catalogue.customId(name: name, w: w, d: d, h: h), items: items)!
                place(piece, proxy: nil)
                category = .custom
            }
        }
        .sheet(isPresented: $showPreview) {
            if let design { PlanPreviewSheet(room: room, design: design, items: items, designs: designs) }
        }
        .sheet(isPresented: $showReactNote) {
            ReactNoteSheet(hostName: room.name(of: .host), initial: reactionTarget?.reactionNote ?? "") { note in
                if let target = reactionTarget { sync.setReaction(target, ok: false, note: note, as: context.realRole) }
            }
        }
    }

    // MARK: Header

    private func header(_ resolved: ResolvedDesign) -> some View {
        let open = items.filter { !$0.isDecided }.count
        let gone = resolved.leaving.count
        // Plan-only rooms never mention sorting: everything is simply in the room.
        let status = !room.sortEnabled ? (items.isEmpty ? "Nothing in the room yet" : "\(items.count) thing\(items.count == 1 ? "" : "s") in the room")
            : open > 0 ? "\(open) not decided, shown where \(open == 1 ? "it is" : "they are")"
            : (gone > 0 ? "All decided, \(gone) leaving" : (items.isEmpty ? "Nothing listed yet" : "All decided"))
        return VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(room.futureUse.isEmpty || room.futureUse == "Still deciding" ? "Proposed layout" : room.futureUse)
                    .font(.sectionTitle).accessibilityAddTraits(.isHeader)
                Text(status).textRole(.secondary)
            }
            if !DeviceCapabilities.isSimulator {
                Button { showAR = true } label: { Label("View in your room", systemImage: "arkit") }
                    .buttonStyle(.app(.neutral))
                    .accessibilityHint("Opens the camera and shows furniture at its real size")
            }
            Button { if isHost { session.showSettings = true } } label: {
                KVRow(label: "Room",
                      value: "\(units.roomLength(Double(room.widthCm))) × \(units.roomLength(Double(room.lengthCm)))\(room.measured ? "" : " · estimate")") {
                    if isHost { Text(room.measured ? "Edit" : "Measure").font(.detailStrong).foregroundStyle(Color.accent) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isHost)
            if isHost {
                FlowLayout(spacing: Space.l) {
                    Button { showShape = true } label: { Label("Walls, door & windows", systemImage: "square.on.square.dashed") }
                        .buttonStyle(.app(.primary, size: .compact))
                    if DeviceCapabilities.canScanRooms {
                        Button { consent { session.showScan = true } } label: {
                            Label(room.isScanned ? "Rescan with LiDAR" : "Scan with LiDAR", systemImage: "viewfinder")
                        }
                        .buttonStyle(.app(.primary, size: .compact))
                    }
                }
            }
            if !room.measured {
                Text("Drafting with estimated dimensions. Fit checks turn on once the room is measured.")
                    .textRole(.hint)
            }
            if isHost && room.futureUse.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    SectionLabel("What will this room become?")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s) {
                            ForEach(NewRoomFlow.futureOptions.filter { $0 != "Still deciding" }, id: \.self) { option in
                                AppChip(title: option, isSelected: false) { room.futureUse = option; sync.save(room) }
                            }
                            AppChip(title: "Something else…", isSelected: false) { session.showSettings = true }
                        }
                    }
                    .scrollClipDisabled()
                }
            }
        }
    }

    // MARK: Versions

    private var versions: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ChipPicker(
                options: [.init(value: UUID?.none, title: "Current room")] + designs.map {
                    .init(value: Optional($0.id), title: $0.name, symbol: $0.guestLikes ? "hand.thumbsup.fill" : nil,
                          symbolLabel: "Looks good to \(room.name(of: .guest))")
                },
                selection: Binding(get: { design?.id }, set: { id in pick(designs.first { $0.id == id }) }),
                accessibilityLabel: "Room versions")
            if isHost {
                FlowLayout(spacing: Space.l) {
                    if let design, !design.locked, !design.livePlacements.isEmpty {
                        Button {
                            let v = DesignActions.saveVersion(of: design, room: room, existing: designs, sync: sync)
                            sync.activity = ActivityEvent(text: "Saved as \(v.name)", symbol: "checkmark", status: nil)
                        } label: { Label("Save a version", systemImage: "plus") }
                            .buttonStyle(.app(.primary, size: .compact))
                    }
                    if let design, !design.livePlacements.isEmpty {
                        Button { showPreview = true } label: { Label("Preview plan", systemImage: "eye") }
                            .buttonStyle(.app(.primary, size: .compact, width: .hug))
                    }
                }
                if let sharedDesign, room.hasGuest {
                    Text("Shared with \(room.name(of: .guest)): \(sharedDesign.name)").textRole(.secondary)
                }
            }
        }
    }

    private func pick(_ d: Design?) {
        session.planDesignPicked = true
        session.planDesignId = d?.id
        selectedPiece = nil
    }

    // MARK: Plan

    private func plan(_ resolved: ResolvedDesign) -> some View {
        // The piece just placed pulses for a moment (a steady outline with Reduce Motion).
        TimelineView(.animation(paused: highlight == nil || reduceMotion)) { time in
            planView(resolved, glow: glow(at: time.date))
        }
    }

    /// 0…1…0 twice over 1.6 s after a piece is placed; 0 afterwards and with Reduce Motion.
    private func glow(at date: Date) -> Double {
        guard let h = highlight, !reduceMotion else { return 0 }
        let t = date.timeIntervalSince(h.at)
        guard t < 1.6 else { return 0 }
        return sin(t / 0.8 * .pi).magnitude
    }

    private func planView(_ resolved: ResolvedDesign, glow: Double) -> some View {
        let zoneId: Int? = if case .zone(let id) = fitMode { id } else { nil }
        return FloorPlanView(
            room: room, entries: resolved.entries, showGhosts: showHidden || design == nil,
            selectedId: selectedPiece, highlightId: highlight?.placementId, glow: glow,
            onSelect: { id in selectedPiece = id },
            zones: canEditDesign ? zones : [], selectedZone: zoneId,
            onSelectZone: { id in fitMode = id.map { .zone($0) } ?? .any },
            onMovePiece: canEditDesign ? { id, x, z in
                if let p = resolved.pieces.first(where: { $0.placement.id == id })?.placement {
                    DesignActions.move(p, x: x, z: z, sync: sync)
                }
            } : nil)
            .card(padding: Space.l, radius: Radius.cardLarge)
    }

    private func pieceBar(_ entry: PlanEntry, placement: DesignPlacement, piece: CatalogPiece) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(piece.name).textRole(.bodyStrong)
                    Text("\(units.dims(piece.w, piece.d, piece.h)) · turned \(Int(placement.yawDeg))°").textRole(.secondary)
                    if let problem = entry.problem {
                        Label(problem, systemImage: "exclamationmark.triangle").font(.detailStrong).foregroundStyle(Color.letGo)
                    } else {
                        Label(room.measured ? "Fits the floor space" : "Estimate · measure to check fit",
                              systemImage: room.measured ? "checkmark" : "ruler")
                            .font(.detailStrong).foregroundStyle(room.measured ? Color.keep : Color.textSecondary)
                    }
                }
                Spacer()
            }
            AdaptiveStack(spacing: Space.s) {
                Button { DesignActions.rotate(placement, by: 90, piece: piece, room: room, sync: sync) } label: { Label("Rotate 90°", systemImage: "arrow.clockwise") }
                    .buttonStyle(.app(.neutral, size: .compact, width: .hug))
                Button("Details") { detailPiece = piece }
                    .buttonStyle(.app(.neutral, size: .compact, width: .hug))
                Spacer()
                IconButton(symbol: "trash", label: "Remove \(piece.name)", role: .destructive, filled: true) {
                    DesignActions.remove(placement, sync: sync)
                    selectedPiece = nil
                }
            }
            // Moving without dragging (VoiceOver, Switch Control, or just precision).
            HStack(spacing: Space.s) {
                Text("Move").textRole(.secondary)
                nudge("arrow.left", "Move left") { DesignActions.move(placement, x: placement.xCm - 10, z: placement.zCm, sync: sync) }
                nudge("arrow.up", "Move toward the back wall") { DesignActions.move(placement, x: placement.xCm, z: placement.zCm - 10, sync: sync) }
                nudge("arrow.down", "Move toward the front") { DesignActions.move(placement, x: placement.xCm, z: placement.zCm + 10, sync: sync) }
                nudge("arrow.right", "Move right") { DesignActions.move(placement, x: placement.xCm + 10, z: placement.zCm, sync: sync) }
            }
            HStack(spacing: Space.s) {
                Text("Turn").textRole(.secondary)
                nudge("arrow.counterclockwise", "Turn 15 degrees left") { DesignActions.rotate(placement, by: -15, piece: piece, room: room, sync: sync) }
                nudge("arrow.clockwise", "Turn 15 degrees right") { DesignActions.rotate(placement, by: 15, piece: piece, room: room, sync: sync) }
            }
        }
        .card(padding: Space.l, radius: Radius.tile)
    }

    private func nudge(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        IconButton(symbol: symbol, label: label, filled: true, action: action)
    }

    @ViewBuilder private func notes(_ resolved: ResolvedDesign) -> some View {
        let bad = resolved.problems.count
        if bad > 0 {
            NoteBar(text: "\(bad) placement\(bad == 1 ? " needs" : "s need") a look: something changed underneath.",
                    symbol: "exclamationmark.triangle", tone: .warning)
        }
        if design != nil, let summary = DesignResolver.hiddenSummary(resolved.leaving) {
            NoteBar(text: summary, symbol: "eye.slash") {
                // The plan redraws at once (no "items leaving" animation), with or without Reduce Motion.
                Button(showHidden ? "Hide them" : "Show them") { withMotion(reduceMotion: reduceMotion) { showHidden.toggle() } }
                    .frame(minHeight: Size.tapTarget)
            }
        }
        if let design, isHost {
            ForEach(resolved.conflicts) { item in
                NoteBar(text: "You moved the \(item.name.lowercased()) in \(design.name), but it’s now marked \(item.status.shortLabel).",
                        symbol: "exclamationmark.triangle", tone: .warning) {
                    if !design.locked {
                        Button("Remove") { DesignActions.clearPlacement(for: item, in: design, sync: sync) }.frame(minHeight: Size.tapTarget)
                    }
                }
            }
        }
    }

    // MARK: Reaction

    /// What the guest reacts to: the shared version, else the one on screen.
    private var reactionTarget: Design? { sharedDesign ?? design }

    @ViewBuilder private var reaction: some View {
        if isHost {
            if let target = sharedDesign ?? designs.first(where: { $0.guestLikes || $0.reactionNote != nil }),
               target.guestLikes || target.reactionNote != nil {
                let guest = room.name(of: .guest)
                NoteBar(text: target.guestLikes ? "\(guest): looks good" : "\(guest): one thing — “\(target.reactionNote ?? "")”")
            }
        } else if let target = reactionTarget, !session.previewAsGuest || !room.guestHasJoined {
            HStack(spacing: Space.s) {
                Button { sync.setReaction(target, ok: true, note: nil, as: context.realRole) } label: {
                    Label("Looks good", systemImage: "checkmark")
                }
                .buttonStyle(.app(target.likes(context.realRole) ? .primary : .neutral, size: .compact, width: .hug))
                .accessibilityAddTraits(target.likes(context.realRole) ? .isSelected : [])
                Button { showReactNote = true } label: { Label("One thing…", systemImage: "text.bubble") }
                    .buttonStyle(.app(target.reactionNote != nil ? .primary : .neutral, size: .compact, width: .hug))
            }
            if target.id == sharedDesign?.id {
                Text("\(room.name(of: .host)) shared \(target.name) with you.").textRole(.hint)
            }
        }
    }

    // MARK: Guest list

    private func pieceList(_ resolved: ResolvedDesign) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(design == nil ? "As it is now" : "In this version")
            if resolved.pieces.isEmpty {
                Text("Nothing added.").textRole(.secondary)
            } else {
                ForEach(resolved.pieces, id: \.placement.id) { entry in
                    HStack {
                        Text(entry.piece.name)
                        Spacer()
                        Text(entry.piece.price > 0 ? entry.piece.price.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                                                   : (entry.piece.source == .custom ? "Own piece" : "Yours"))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.vertical, Space.s)
                    .accessibilityElement(children: .combine)
                    Hairline()
                }
            }
        }
    }

    // MARK: Catalogue

    private var activeSpace: FitSpace? {
        switch fitMode {
        case .any: nil
        case .custom: customSpace
        case .zone(let id):
            zones.first { $0.id == id }.map { FitSpace(w: $0.rect.w, d: $0.rect.d, h: Double(room.heightCm)) }
        }
    }

    private var catalogueChoices: [CatalogPiece] {
        switch category {
        case .existing:
            items.filter { !room.leaves($0) && !$0.category.isFlat }.map(Catalogue.existing)
        case .custom:
            Array(Set(designs.flatMap(\.livePlacements).compactMap(\.catalogId).filter { $0.hasPrefix("custom|") }))
                .sorted().compactMap { Catalogue.piece($0, items: items) }
        case .all:
            Catalogue.pieces
        default:
            Catalogue.pieces.filter { $0.category == category }
        }
    }

    private func catalogue(onPlace: @escaping (CatalogPiece) -> Void) -> some View {
        let space = activeSpace
        let all = catalogueChoices
        let fitting = space.map { s in all.filter { Fit.of($0, in: s) != .no } } ?? all
        let shown = showNoFit ? all : fitting
        let zoneLabel: String? = if case .zone(let id) = fitMode { zones.first { $0.id == id }?.label } else { nil }

        return VStack(alignment: .leading, spacing: Space.m) {
            Text("Add furniture").font(.cardTitle).accessibilityAddTraits(.isHeader)
            ChipPicker(options: CatalogPiece.Category.allCases.map { .init(value: $0, title: $0.label) }, selection: $category,
                       accessibilityLabel: "Furniture categories")

            DisclosureGroup(isExpanded: $showFit) {
                VStack(alignment: .leading, spacing: Space.s) {
                    PickRow(title: "All sizes", isSelected: fitMode == .any) { fitMode = .any }
                    ForEach(zones) { zone in
                        PickRow(title: zone.label, subtitle: "\(units.roomLength(zone.rect.w)) × \(units.roomLength(zone.rect.d)) freed up",
                                isSelected: fitMode == .zone(zone.id)) { fitMode = .zone(zone.id) }
                    }
                    PickRow(title: "Enter dimensions", isSelected: fitMode == .custom) { fitMode = .custom }
                    if fitMode == .custom {
                        DimensionFields(units: units, w: $customSpace.w, d: $customSpace.d, h: $customSpace.h)
                    }
                }
                .padding(.top, Space.s)
            } label: {
                HStack {
                    Label("Fit filter", systemImage: "ruler")
                    Spacer()
                    Text(fitMode == .any ? "Any size" : fitMode == .custom ? "Custom dimensions" : (zoneLabel ?? "Room space"))
                        .fontWeight(.medium).foregroundStyle(Color.textPrimary)
                }
                .font(.detail)
                .foregroundStyle(Color.textSecondary)
                .frame(minHeight: Size.tapTarget)
            }
            .tint(Color.iconNeutral)

            if let space {
                HStack(spacing: Space.xs) {
                    Text("\(fitting.count) piece\(fitting.count == 1 ? "" : "s") fit \(zoneLabel.map { "the \($0.lowercased())" } ?? "\(units.roomLength(space.w)) × \(units.roomLength(space.d))").")
                    if all.count > fitting.count {
                        Button(showNoFit ? "Hide ones that don’t fit" : "Show \(all.count - fitting.count) that don’t") { showNoFit.toggle() }
                            .buttonStyle(.app(.primary, size: .compact))
                    }
                }
                .textRole(.secondary)
            }
            if category == .custom {
                Button { showCustom = true } label: { Label("Add a piece by its size", systemImage: "plus") }
                    .buttonStyle(.app(.primary, size: .compact))
            }
            if category == .existing {
                Text(room.sortEnabled ? "Things that are staying. They’re already in the plan; place a copy to try it somewhere else."
                                      : "Things already in the room. They’re in the plan; place a copy to try it somewhere else.")
                    .textRole(.hint)
            }

            if shown.isEmpty {
                Text(category == .custom ? "Nothing of your own yet." : "Nothing in this category fits. Try another space or category.")
                    .textRole(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.m)], spacing: Space.m) {
                    ForEach(shown) { piece in
                        PieceCard(piece: piece, units: units, fit: space.flatMap { room.measured ? Fit.of(piece, in: $0) : nil },
                                  room: room, onDetails: { detailPiece = piece }) { onPlace(piece) }
                    }
                }
            }
        }
        .padding(.top, Space.s)
    }

    /// The live AR view, showing this plan version. Moves made there save to the plan.
    private func arView(_ resolved: ResolvedDesign) -> some View {
        let plan = resolved.pieces.map {
            ARPlanPiece(id: $0.placement.id, piece: $0.piece, x: $0.placement.xCm, z: $0.placement.zCm, yaw: $0.placement.yawDeg)
        }
        let selected = selectedPiece.flatMap { id in resolved.pieces.first { $0.placement.id == id }?.piece }
        // Real things the plan changes: outlined if they're leaving, marked where they'll move to.
        let markers: [ARMarker] = resolved.entries.compactMap { e in
            let kind: ARMarker.Kind
            switch e.style {
            case .leaving: kind = .leaving
            case .moved: kind = .movesHere
            default: return nil
            }
            return ARMarker(id: e.id, kind: kind, name: e.name, x: e.xCm, z: e.zCm, yaw: e.yawDeg,
                            w: e.widthCm, d: e.depthCm, h: e.heightCm ?? 75)
        }
        return ARRoomView(
            room: room, choices: arChoices, initialPiece: arInitialPiece ?? selected,
            plan: plan, markers: markers, canEdit: canEditDesign,
            onMove: { id, x, z, yaw in
                guard let p = resolved.pieces.first(where: { $0.placement.id == id }) else { return }
                // Same rules as dragging in the plan: inside the walls, square to 15°.
                let c = PlacementCheck.constrain(x: x, z: z, w: p.piece.w, d: p.piece.d, yaw: yaw, room: room, snap: 0)
                DesignActions.place(p.placement, x: c.x, z: c.z, yawDeg: yaw, sync: sync)
            },
            onRemove: { id in
                if let p = resolved.pieces.first(where: { $0.placement.id == id })?.placement { DesignActions.remove(p, sync: sync) }
            },
            onAdd: { piece, x, z, yaw in
                guard isHost else { return nil }
                let target = canEditDesign && design != nil ? design! : DesignActions.workingDesign(in: room, existing: designs, sync: sync)
                if target.id != design?.id { pick(target) }
                let (placement, _) = DesignActions.addPiece(piece, to: target, room: room, items: items, zone: nil, sync: sync)
                let c = PlacementCheck.constrain(x: x, z: z, w: piece.w, d: piece.d, yaw: yaw, room: room, snap: 0)
                DesignActions.place(placement, x: c.x, z: c.z, yawDeg: yaw, sync: sync)
                return placement.id
            })
    }

    /// What can be placed in AR: pieces already in this plan first, then the catalogue.
    private var arChoices: [CatalogPiece] {
        let inPlan = resolved.pieces.map(\.piece)
        var seen = Set<String>()
        return (inPlan + Catalogue.pieces).filter { seen.insert($0.id).inserted }
    }

    static let roomViewAnchor = "room-view"

    /// Places a piece, then makes it obvious: back up to the room, the piece selected and
    /// highlighted, and a banner ("Added Armchair. Drag it to move it.", with Undo).
    private func place(_ piece: CatalogPiece, proxy: ScrollViewProxy?) {
        let target = canEditDesign && design != nil ? design! : DesignActions.workingDesign(in: room, existing: designs, sync: sync)
        if target.id != design?.id { pick(target) }
        let zone: FreeZone? = if case .zone(let id) = fitMode { zones.first { $0.id == id } } else { nil }
        let (placement, fits) = DesignActions.addPiece(piece, to: target, room: room, items: items, zone: zone, sync: sync)
        selectedPiece = placement.id
        let added = JustPlaced(placementId: placement.id, name: piece.name, fits: fits)
        highlight = added
        justPlaced = added
        withMotion(Motion.screen, reduceMotion: reduceMotion) { proxy?.scrollTo(Self.roomViewAnchor, anchor: .top) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if highlight?.id == added.id { highlight = nil } }
    }
}

// MARK: - Pieces

private struct PieceCard: View {
    let piece: CatalogPiece
    let units: UnitSystem
    let fit: Fit?
    let room: Room
    /// Long-press menu and VoiceOver action: the piece's details, with "View in your room".
    var onDetails: () -> Void
    var onPlace: () -> Void
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        Button(action: onPlace) {
            VStack(alignment: .leading, spacing: Space.s) {
                ZStack(alignment: .topLeading) {
                    PieceImage(piece: piece, room: room)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1.2, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
                    if let fit {
                        AppTag(kind: .fit(fit), text: fit.label)
                            .padding(Space.s)
                    }
                }
                Text(piece.name).font(.detailStrong).foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(units.dims(piece.w, piece.d, piece.h)).font(.detail).foregroundStyle(Color.textSecondary)
                Text(piece.style).font(.detail).foregroundStyle(Color.textSecondary)
                Label("Place", systemImage: "plus").font(.detailStrong).foregroundStyle(Color.accent)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .card(padding: Space.m, radius: Radius.tile)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Place \(piece.name), \(units.dims(piece.w, piece.d, piece.h))\(fit.map { ", \($0.label)" } ?? "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Details and View in your room", onDetails)
        .contextMenu {
            Button("Place in plan", systemImage: "plus", action: onPlace)
            Button("Details", systemImage: "info.circle", action: onDetails)
        }
    }
}

/// Thumbnail for a piece: a photo crop for things already in the room, else its kind's icon.
private struct PieceImage: View {
    let piece: CatalogPiece
    let room: Room
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        if case .existing(let id) = piece.source, let item = room.liveItems.first(where: { $0.id == id }),
           let x = item.pinX, let y = item.pinY,
           let crop = PhotoCrops.crop(roomId: room.id, photo: item.pinPhoto, at: CGPoint(x: x, y: y), revision: sync.photoRevision) {
            Image(uiImage: crop).resizable().scaledToFill()
        } else {
            CategoryGlyph(category: piece.kind, colorHex: piece.colorHex, glyph: .medium)
        }
    }
}

private struct PieceDetailSheet: View {
    let piece: CatalogPiece
    let units: UnitSystem
    /// "View in your room" (opens AR with this piece chosen, lined up with the plan).
    var onViewInRoom: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.l) {
                CategoryGlyph(category: piece.kind, colorHex: piece.colorHex, glyph: .hero)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline) {
                    Text(piece.price > 0 ? piece.price.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                                         : (piece.source == .custom ? "Own piece" : "Yours"))
                        .font(.sectionTitle)
                    Spacer()
                    Text(units.dims(piece.w, piece.d, piece.h)).foregroundStyle(Color.textSecondary)
                }
                Text(piece.style).foregroundStyle(Color.textSecondary)
                if piece.price > 0 {
                    Text("Sample price for planning. Store links aren’t part of the app yet.")
                        .textRole(.hint)
                }
                if !DeviceCapabilities.isSimulator {
                    Button(action: onViewInRoom) { Label("View in your room", systemImage: "arkit") }
                        .buttonStyle(.app)
                        .accessibilityHint("Opens the camera and shows the \(piece.name.lowercased()) at its real size")
                }
                Spacer()
            }
            .padding(Space.page)
            .appSheet()
            .appNavigation(piece.name)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// "Your own piece": a thing you already own or plan to buy, by its size.
private struct CustomPieceSheet: View {
    let units: UnitSystem
    var onSave: (String, Double, Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var w = 100.0
    @State private var d = 50.0
    @State private var h = 75.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("A piece you already own or plan to buy.").foregroundStyle(Color.textSecondary)
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Name")
                        TextField("Grandma’s dresser", text: $name, prompt: Text("Grandma’s dresser").foregroundStyle(Color.textSecondary)).textFieldStyle(.app)
                    }
                    DimensionFields(units: units, w: $w, d: $d, h: $h)
                    Button("Place in plan") {
                        onSave(name.trimmed, w, d, h)
                        dismiss()
                    }
                    .buttonStyle(.app)
                    .disabled(w < 5 || d < 5)
                }
                .padding(Space.page)
            }
            .appSheet()
            .appNavigation("Your own piece")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Preview and reaction

/// "Preview plan": the plan, what's in it and roughly what it costs, then share it.
private struct PlanPreviewSheet: View {
    let room: Room
    let design: Design
    let items: [Item]
    let designs: [Design]
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @Environment(RoomSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        let resolved = DesignResolver.resolve(items: items, design: design, room: room)
        let units = room.unitSystem
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    let cost = resolved.pieceCost
                    Text("\(room.futureUse.isEmpty ? "Proposed layout" : room.futureUse) · \(resolved.pieces.count) piece\(resolved.pieces.count == 1 ? "" : "s")\(cost > 0 ? " · about \(cost.formatted(.currency(code: "USD").precision(.fractionLength(0))))" : "")")
                        .foregroundStyle(Color.textSecondary)
                    FloorPlanView(room: room, entries: resolved.entries)
                        .card(padding: Space.m, radius: Radius.cardLarge)
                    VStack(spacing: Space.xs) {
                        ForEach(resolved.pieces, id: \.placement.id) { entry in
                            HStack {
                                Text(entry.piece.name)
                                Spacer()
                                Text(units.dims(entry.piece.w, entry.piece.d, entry.piece.h)).foregroundStyle(Color.textSecondary)
                            }
                            .padding(.vertical, Space.m)
                            .accessibilityElement(children: .combine)
                            Hairline()
                        }
                    }
                    if room.hasGuest {
                        Button {
                            let shared = DesignActions.share(design, room: room, existing: designs, sync: sync)
                            session.planDesignPicked = true
                            session.planDesignId = shared.id
                            sync.activity = ActivityEvent(text: "Shared with \(room.name(of: .guest))", symbol: "paperplane", status: nil)
                            dismiss()
                        } label: { Label("Share plan with \(room.name(of: .guest))", systemImage: "paperplane") }
                            .buttonStyle(.app(.primary))
                        Text("\(room.name(of: .guest)) sees this version and can react to it.")
                            .textRole(.hint).frame(maxWidth: .infinity)
                    } else {
                        Button {
                            dismiss()
                            router.roomTab = .people
                        } label: { Label("Invite someone to see it", systemImage: "person.2") }
                            .buttonStyle(.app(.neutral))
                    }
                }
                .padding(Space.page)
            }
            .appSheet()
            .appNavigation(design.name)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct ReactNoteSheet: View {
    let hostName: String
    let initial: String
    var onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("\(hostName) will see this with the plan.").foregroundStyle(Color.textSecondary)
                TextField("For example: can the bookshelf stay by the window?", text: $text, prompt: Text("For example: can the bookshelf stay by the window?").foregroundStyle(Color.textSecondary), axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.appArea)
                Button("Send") { onSend(text.trimmed); dismiss() }
                    .buttonStyle(.app)
                    .disabled(text.trimmed.isEmpty)
                Spacer()
            }
            .padding(Space.page)
            .appSheet()
            .appNavigation("One thing")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { text = initial }
        }
        .presentationDetents([.medium])
    }
}
