import SwiftData
import SwiftUI

/// Redesign tab. Never requires sorting: with no decisions it shows every item in place.
/// Things Sort sends out of the room are hidden, with a note and a way to show them.
struct RedesignHomeView: View {
    let room: Room
    @Environment(SyncEngine.self) private var sync
    @Environment(RoomSession.self) private var session
    @Query private var items: [Item]
    @Query private var designs: [Design]
    @State private var selectedId: UUID?
    @State private var showHidden = false

    init(room: Room) {
        self.room = room
        _items = Query(Item.live(in: room.id))
        _designs = Query(Design.live(in: room.id))
    }

    private var context: RoomContext { session.context(room, userId: sync.userId) }
    private var design: Design? { designs.first { $0.id == selectedId } ?? designs.first }
    private var resolved: ResolvedDesign { DesignResolver.resolve(items: items, design: design) }

    var body: some View {
        Group {
            if items.isEmpty && designs.isEmpty {
                NoItemsYetView(context: context,
                               message: "Redesign starts with the room exactly as it is. Scan it or add its furniture by hand, then try moving things around and adding new pieces. You don’t need to sort first.")
            } else {
                content
            }
        }
        .background(Color.ssBg)
        .roomChrome(room)
    }

    private var content: some View {
        let resolved = resolved
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !designs.isEmpty || context.canEditRoom { optionPicker }

                VStack(alignment: .leading, spacing: 8) {
                    FloorPlanView(room: room, entries: resolved.entries, showGhosts: showHidden)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(Color.ssStage, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    Text(design?.name ?? "The room as it is now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ssMuted)
                }

                if let summary = DesignResolver.hiddenSummary(resolved.leaving) {
                    note(summary, symbol: "eye.slash") {
                        Button(showHidden ? "Hide them" : "Show them") { withAnimation { showHidden.toggle() } }
                            .font(.subheadline.weight(.semibold))
                    }
                }
                if !resolved.hiddenInDesign.isEmpty {
                    let n = resolved.hiddenInDesign.count
                    note("\(n) thing\(n == 1 ? " is" : "s are") hidden in this design only. Sort still says \(n == 1 ? "it stays" : "they stay").",
                         symbol: "eye.slash") { EmptyView() }
                }
                if let design, context.canEditRoom {
                    ForEach(resolved.conflicts) { item in
                        note("You placed the \(item.name.lowercased()) in \(design.name), but it’s now marked \(item.status.buttonLabel).",
                             symbol: "exclamationmark.triangle") {
                            Button("Remove") { DesignActions.clearPlacement(for: item, in: design, sync: sync) }
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }

                if let design { likeRow(design) }
                primaryAction

                Text("Undecided things stay where they are. Redesigning never changes your Sort decisions.")
                    .font(.footnote)
                    .foregroundStyle(Color.ssMuted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: Pieces

    private var optionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if designs.isEmpty {
                    Chip(title: "As it is now", isOn: true) {}
                }
                ForEach(designs) { d in
                    Chip(title: d.likes(context.me.other) ? "\(d.name) ♥" : d.name, isOn: d.id == design?.id) {
                        selectedId = d.id
                    }
                }
                if context.canEditRoom && designs.count < Design.maxPerRoom {
                    Button {
                        if let new = DesignActions.createDesign(in: room, existing: designs, copying: design, sync: sync) {
                            selectedId = new.id
                        }
                    } label: {
                        Label("New option", systemImage: "plus").font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
        }
    }

    private func likeRow(_ design: Design) -> some View {
        let liked = design.likes(context.me)
        let other = design.likes(context.me.other)
        return HStack(spacing: 10) {
            Button {
                sync.setLike(design, liked: !liked, as: context.realRole)
            } label: {
                Label(liked ? "You like this" : "I like this one", systemImage: liked ? "heart.fill" : "heart")
            }
            .buttonStyle(.pill(liked ? .accent : .secondary, fullWidth: false))
            .disabled(session.previewAsGuest)
            if other {
                Tag(text: "\(room.name(of: context.me.other)) likes this", symbol: "heart.fill",
                    foreground: .ssAccentInk, background: .ssAccentSoft)
            }
        }
    }

    @ViewBuilder private var primaryAction: some View {
        if context.canEditRoom {
            Button {
                let target = design ?? DesignActions.createDesign(in: room, existing: designs, copying: nil, sync: sync)
                if let target {
                    selectedId = target.id
                    session.redesignPath.append(.design(target.id))
                }
            } label: {
                Label(design == nil ? "Start a design" : "Edit \(design!.name) in 3D", systemImage: "cube")
            }
            .buttonStyle(.pill)
        } else if let design {
            Button { session.redesignPath.append(.design(design.id)) } label: {
                Label("View \(design.name) in 3D", systemImage: "cube")
            }
            .buttonStyle(.pill(.secondary))
        } else {
            Text("\(room.name(of: .host)) hasn’t made any designs yet. You can see the room as it is above.")
                .font(.subheadline)
                .foregroundStyle(Color.ssMuted)
        }
    }

    private func note<Accessory: View>(_ text: String, symbol: String,
                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color.ssAccentInk)
            Text(text).font(.subheadline).foregroundStyle(Color.ssAccentInk)
            Spacer(minLength: 8)
            accessory()
        }
        .padding(12)
        .background(Color.ssAccentSoft, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Placeholder until the 3D dollhouse editor lands.
struct DesignEditorView: View {
    let roomId: UUID
    let designId: UUID

    var body: some View {
        ContentUnavailableView("3D editing is coming next", systemImage: "cube",
                               description: Text("You’ll be able to move, turn and hide things here, add new furniture, and view the design in your room with AR."))
            .navigationTitle("Design")
            .navigationBarTitleDisplayMode(.inline)
    }
}
