import SwiftData
import SwiftUI

/// Room tab: what the room is, its goals and how each is going, and who can see it.
/// The host can change the goals here ("Room goals…") or add the one that's missing.
struct RoomOverviewView: View {
    let room: Room
    @Environment(SyncEngine.self) private var sync
    @Environment(RoomSession.self) private var session
    @Environment(Router.self) private var router
    @Query private var items: [Item]
    @Query private var designs: [Design]

    init(room: Room) {
        self.room = room
        _items = Query(Item.live(in: room.id))
        _designs = Query(Design.live(in: room.id))
    }

    private var context: RoomContext { session.context(room, userId: sync.userId) }
    private var canEdit: Bool { context.canEditRoom }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                if !room.transformLine.isEmpty {
                    Text(room.transformLine).textRole(.secondary)
                }
                if let photo = RoomPhotos.image(roomId: room.id, index: 0, revision: sync.photoRevision) {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: Size.cardImageMax)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
                        .accessibilityLabel("Photo of the room")
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    SectionLabel("Goals")
                    VStack(spacing: 0) {
                        ForEach(room.goals) { goal in
                            goalRow(goal)
                            if goal != room.goals.last { Hairline(inset: Space.l + Size.iconCircle + Space.m) }
                        }
                    }
                    .listGroup()
                    if canEdit {
                        Button { session.showGoals = true } label: { Label("Room goals…", systemImage: "target") }
                            .buttonStyle(.app(.primary, size: .compact))
                    }
                }

                if canEdit, let missing = RoomGoal.allCases.first(where: { !room.isEnabled($0) }) {
                    addGoalCard(missing)
                }

                Button { if canEdit { session.showSettings = true } } label: {
                    KVRow(label: "Size",
                          value: "\(room.unitSystem.roomLength(Double(room.widthCm))) × \(room.unitSystem.roomLength(Double(room.lengthCm)))\(room.measured ? "" : " · estimate")") {
                        if canEdit { Text("Edit").font(.detailStrong).foregroundStyle(Color.accent) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canEdit)

                WhoCanSeeThisLink()
            }
            .pagePadding()
            .padding(.bottom, Size.floatingClearance)
        }
        .pageBackground()
        .roomChrome(room)
    }

    /// "Sorting · 7 of 11 decided  ›": opens that goal's tab.
    private func goalRow(_ goal: RoomGoal) -> some View {
        Button { router.roomTab = goal == .sort ? .items : .plan } label: {
            HStack(spacing: Space.m) {
                IconCircle(symbol: goal.symbol, tone: goal.tone)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(goal.tag).textRole(.bodyStrong)
                    Text(RoomGoalStatus.text(goal, room: room, items: items, designs: designs, me: context.me))
                        .textRole(.secondary)
                }
                Spacer(minLength: 0)
                RowChevron()
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .frame(minHeight: Size.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(goal == .sort ? RoomTab.items.title : RoomTab.plan.title)")
    }

    /// "Want to plan this room too? Add planning".
    private func addGoalCard(_ goal: RoomGoal) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                IconCircle(symbol: goal.symbol, tone: goal.tone)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(goal == .plan ? "Want to plan this room too?" : "Want to sort what’s in here too?")
                        .textRole(.bodyStrong)
                    Text(goal == .plan ? "Try layouts and furniture for the room." : "Decide what stays and what goes. Nothing has to leave the room.")
                        .textRole(.secondary)
                }
            }
            Button { add(goal) } label: { Label(goal == .plan ? "Add planning" : "Add sorting", systemImage: "plus") }
                .buttonStyle(.app(.primary, size: .compact))
        }
        .card(padding: Space.l, radius: Radius.tile)
    }

    private func add(_ goal: RoomGoal) {
        switch goal {
        case .sort: room.sortEnabled = true
        case .plan: room.planEnabled = true
        }
        sync.save(room)
        router.roomTab = goal == .sort ? .items : .plan
    }
}

/// One-line status for a goal, on Home and the Room tab: "7 of 11 decided", "2 layouts".
enum RoomGoalStatus {
    static func text(_ goal: RoomGoal, room: Room, items: [Item], designs: [Design], me: Role) -> String {
        switch goal {
        case .sort:
            let mine = me == .guest ? SortRules.items(items, belongingTo: .guest) : items
            guard !mine.isEmpty else { return "Nothing listed yet" }
            let decided = mine.filter(\.isDecided).count
            return decided == mine.count ? "All \(mine.count) decided" : "\(decided) of \(mine.count) decided"
        case .plan:
            // The working plan plus saved versions; an untouched working plan doesn't count.
            let n = designs.filter { $0.locked || !$0.livePlacements.isEmpty }.count
            return n == 0 ? "No layouts yet" : "\(n) layout\(n == 1 ? "" : "s")"
        }
    }
}
