import SwiftUI

// Tags, text roles, cards, notes, page and sheet backgrounds, navigation and layout helpers.

// MARK: - Text roles

/// How a piece of text is used. Sets both font and colour from Theme.
enum TextRole: CaseIterable {
    case largeTitle, screenTitle, sectionTitle, cardTitle, body, bodyStrong, label, secondary, hint, error

    var font: Font {
        switch self {
        case .largeTitle: .largeTitleText
        case .screenTitle: .screenTitle
        case .sectionTitle: .sectionTitle
        case .cardTitle: .cardTitle
        case .body: .bodyText
        case .bodyStrong, .label: .bodyStrong
        case .secondary, .hint: .detail
        case .error: .detailStrong
        }
    }

    var color: Color {
        switch self {
        case .secondary, .hint: .textSecondary
        case .error: .danger
        default: .textPrimary
        }
    }
}

extension View {
    func textRole(_ role: TextRole) -> some View {
        font(role.font).foregroundStyle(role.color)
    }
}

// MARK: - Surfaces

private struct OnWhiteSurfaceKey: EnvironmentKey { static let defaultValue = false }
private struct PageBackgroundKey: EnvironmentKey { static let defaultValue = Theme.background }

extension EnvironmentValues {
    /// True inside sheets and other white areas: cards there use a Mist fill and no shadow.
    var onWhiteSurface: Bool {
        get { self[OnWhiteSurfaceKey.self] }
        set { self[OnWhiteSurfaceKey.self] = newValue }
    }

    /// Which page gradient to draw (Theme.background unless a preview overrides it).
    var pageBackgroundStyle: PageBackground {
        get { self[PageBackgroundKey.self] }
        set { self[PageBackgroundKey.self] = newValue }
    }
}

private struct PageBackgroundModifier: ViewModifier {
    @Environment(\.pageBackgroundStyle) private var style
    func body(content: Content) -> some View {
        content
            .background { style.gradient.ignoresSafeArea() }
            .environment(\.onWhiteSurface, false)
    }
}

private struct BarBackgroundModifier: ViewModifier {
    @Environment(\.pageBackgroundStyle) private var style
    @Environment(\.onWhiteSurface) private var onWhite
    func body(content: Content) -> some View {
        content
            .background { (onWhite ? Color.surface : style.bottom).ignoresSafeArea() }
            .overlay(alignment: .top) { Hairline() }
    }
}

private struct CardModifier: ViewModifier {
    let padding: CGFloat
    let radius: CGFloat
    @Environment(\.onWhiteSurface) private var onWhite

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(onWhite ? Color.surfaceMuted : Color.surface,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .elevation(.card, !onWhite)
            .environment(\.onWhiteSurface, !onWhite)
    }
}

extension View {
    /// The soft gradient behind every main screen.
    func pageBackground() -> some View { modifier(PageBackgroundModifier()) }

    /// Behind a bar pinned to the bottom of a screen (the create flow's footer).
    func barBackground() -> some View { modifier(BarBackgroundModifier()) }

    /// A card: white with the card shadow on the page gradient, Mist with no shadow on white.
    /// Never a grey outline.
    func card(padding: CGFloat = Space.l, radius: CGFloat = Radius.card) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }

    /// A rounded group of rows (no inner padding; rows bring their own).
    func listGroup() -> some View {
        card(padding: 0).clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// Page content padding: 24 points at the sides.
    func pagePadding() -> some View { padding(.horizontal, Space.page).padding(.vertical, Space.m) }

    /// The look behind photos and plans.
    func stage(_ fill: Color = .stage) -> some View {
        frame(maxWidth: .infinity)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
    }

    /// Sheets: white, 32-point corners; cards inside them switch to Mist.
    func appSheet() -> some View {
        self.background(Color.surface)
            .environment(\.onWhiteSurface, true)
            .presentationBackground(Color.surface)
            .presentationCornerRadius(Radius.sheet)
    }

    /// Screen title with no heavy header bar: the page gradient shows through.
    func appNavigation(_ title: String, large: Bool = false) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(large ? .large : .inline)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

extension Theme {
    /// UIKit parts SwiftUI can't style directly: semibold Ink large titles. Call once at launch.
    @MainActor static func configureAppearance() {
        let ink = UIColor(named: "textPrimary") ?? .label
        let large = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
        let inline = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.medium]])
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: UIFont(descriptor: large, size: 0), .foregroundColor: ink]
        bar.titleTextAttributes = [.font: UIFont(descriptor: inline, size: 0), .foregroundColor: ink]
    }
}

// MARK: - Tags

/// A soft gradient capsule, 32 points tall: icon + medium-weight word, no outline. Not tappable.
/// For owners ("Mine", "Sam’s") and decided status ("Staying", "Going to Sam").
struct AppTag: View {
    enum Kind: Equatable {
        case neutral, suggestion
        case decision(ItemStatus)
        case owner(Role)
        case fit(Fit)
        case tone(Tone)
    }

    let kind: Kind
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: Space.xs) {
            if let icon = symbol ?? defaultSymbol { Image(systemName: icon).accessibilityHidden(true) }
            Text(text)
        }
        .font(.detailStrong)
        .foregroundStyle(tone.text)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xs)
        .frame(minHeight: Size.tag)
        .background(tone.fill, in: Capsule())
    }

    private var defaultSymbol: String? {
        switch kind {
        case .decision(let s): s.icon
        case .suggestion: "text.bubble"
        case .fit(let f): f == .no ? "xmark" : "checkmark"
        case .owner: "person"
        default: nil
        }
    }

    private var tone: Tone {
        switch kind {
        case .neutral: .brown
        case .suggestion: .sage
        case .decision(let s): s.tone
        case .owner(let r): r.tone
        case .fit(.ok): .sage
        case .fit(.tight): .brown
        case .fit(.no): .brick
        case .tone(let t): t
        }
    }
}

/// An item's decision, from `me`'s point of view, as a tag.
struct StatusTag: View {
    let item: Item
    let room: Room
    let me: Role

    var body: some View {
        AppTag(kind: .decision(item.status), text: SortRules.statusText(item, room: room, me: me))
    }
}

/// Number on a pin or thumbnail.
struct NumberBadge: View {
    enum Placement { case onSurface, onPhoto }

    let number: Int
    var isSelected = false
    var size: CGFloat = Size.pin
    /// Ring colour (a pin's decision); the accent by default.
    var ring: Color = .accent
    /// On photos the badge stays white in dark mode and gets a shadow, so it reads on any picture.
    var placement: Placement = .onSurface

    var body: some View {
        Text("\(number)")
            .font(.badge)
            .foregroundStyle(isSelected ? Color.onAccent : (placement == .onPhoto ? Color.onPhotoText : Color.textPrimary))
            .frame(minWidth: size, minHeight: size)
            .background(isSelected ? Color.accent : (placement == .onPhoto ? Color.photoBadge : Color.surface), in: Circle())
            .overlay(Circle().strokeBorder(isSelected ? Color.accent : ring, lineWidth: size >= Size.pin ? Stroke.bold : Stroke.regular))
            .elevation(.card, placement == .onPhoto)
    }
}

/// The name shown under a selected pin on a photo.
struct PhotoLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.badge)
            .foregroundStyle(Color.photoBadge)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(Color.onPhotoText.opacity(Opacity.pinLabel), in: Capsule())
            .fixedSize()
    }
}

// MARK: - Rows and notes

/// A 1-point decorative line (works inside any stack, unlike Divider in overlays).
struct Hairline: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle().fill(Color.divider).frame(height: Stroke.hairline).padding(.leading, inset)
    }
}

/// A message on a soft gradient with an optional action. `.info` is sage, `.warning` brick.
struct NoteBar<Accessory: View>: View {
    enum Tone: CaseIterable { case info, warning }
    let text: String
    var symbol = "text.bubble"
    var tone: Tone = .info
    @ViewBuilder var accessory: Accessory

    private var colours: SharedSpace.Tone { tone == .info ? .sage : .brick }

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(text).font(.detail).frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .foregroundStyle(colours.text)
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, minHeight: Size.tapTarget, alignment: .leading)
        .background(colours.fill, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

extension NoteBar where Accessory == EmptyView {
    init(text: String, symbol: String = "text.bubble", tone: Tone = .info) {
        self.init(text: text, symbol: symbol, tone: tone) { EmptyView() }
    }
}

/// "Room code   K7M2Q   Copy": a label, a value and an optional action, on a card.
struct KVRow<Accessory: View>: View {
    let label: String
    let value: String
    var valueFont: Font = .bodyStrong
    var tracking: CGFloat = 0
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(label).textRole(.secondary)
                Text(value).font(valueFont).kerning(tracking).foregroundStyle(Color.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            accessory
        }
        .card(padding: Space.l, radius: Radius.tile)
    }
}

/// The ">" at the end of a tappable row.
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.detail).foregroundStyle(Color.iconNeutral).accessibilityHidden(true)
    }
}

/// Medium-weight heading above a group ("Your decision", "Belongs to").
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).textRole(.label).accessibilityAddTraits(.isHeader)
    }
}

/// A tinted icon circle (choice tiles, rows).
struct IconCircle: View {
    let symbol: String
    var tone: Tone = .sage
    var body: some View {
        Image(systemName: symbol)
            .font(.button)
            .foregroundStyle(tone.icon)
            .frame(width: Size.iconCircle, height: Size.iconCircle)
            .background(tone.tint, in: Circle())
            .accessibilityHidden(true)
    }
}

/// A big tappable choice ("Take a photo", "Scan with LiDAR").
struct ChoiceTile: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            IconCircle(symbol: symbol)
            Text(title).textRole(.bodyStrong)
            Text(detail).textRole(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: Size.row * 2, alignment: .topLeading)
        .card(padding: Space.l, radius: Radius.tile)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Wraps children onto new lines, like CSS flex-wrap. Used for chip and tag groups.
struct FlowLayout: Layout {
    var spacing: CGFloat = Space.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if extra > width, !rows[rows.count - 1].indices.isEmpty { rows.append(Row()) }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - People and brand

/// A circle with the person's initial (medium weight) on their tint.
struct Avatar: View {
    let name: String
    let role: Role
    /// nil = don't show presence; true/false = online dot / dimmed.
    var online: Bool?
    var size: CGFloat = Size.avatar

    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased())
            .font(.glyph(fitting: size, weight: .medium))
            .foregroundStyle(Color.textPrimary)
            .frame(width: size, height: size)
            .background(role.tone.tint, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                if online == true {
                    Circle().fill(Color.accent)
                        .frame(width: size * Size.onlineDotRatio, height: size * Size.onlineDotRatio)
                        .overlay(Circle().stroke(Color.surface, lineWidth: Stroke.bold))
                }
            }
            .opacity(online == false ? Opacity.offline : 1)
            .accessibilityLabel(online == true ? "\(name), here now" : name)
    }
}

/// The two overlapping squares from the logo. Drawn on a 32-unit grid.
struct BrandMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 32
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4 * s).fill(Color.logoPrimary)
                    .frame(width: 16 * s, height: 16 * s).offset(x: 3 * s, y: 7 * s)
                RoundedRectangle(cornerRadius: 4 * s).fill(Color.logoSecondary)
                    .frame(width: 16 * s, height: 16 * s).offset(x: 13 * s, y: 11 * s)
                Rectangle().fill(Color.logoOverlap.opacity(Opacity.logoOverlap))
                    .frame(width: 6 * s, height: 12 * s).offset(x: 13 * s, y: 11 * s)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Room card

/// A room on the home screen: name, status and progress on the left, an 88-point tile in the
/// room's tint on the right holding its photo.
struct RoomCard: View {
    let name: String
    let plannedUse: String
    let status: String
    /// 0...1 decided, or nil to leave out the bar.
    var progress: Double?
    var image: UIImage?
    var tint: Tone = .sage
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.l))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: Space.l))
        layout {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(name).textRole(.cardTitle)
                if !plannedUse.isEmpty {
                    Text("Planned use: \(plannedUse)").textRole(.secondary)
                }
                Text(status).textRole(.secondary)
                if let progress { ProgressBar(value: progress).padding(.top, Space.s) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            tile
        }
        .card(padding: Space.xl, radius: Radius.cardLarge)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var tile: some View {
        ZStack {
            tint.tint
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "sofa").font(.glyph(.medium)).foregroundStyle(tint.icon)
            }
        }
        .frame(width: Size.roomTile, height: Size.roomTile)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Empty and banner

/// Friendly "nothing here yet" state used by Items and Room plan.
struct NoItemsYetView: View {
    let context: RoomContext
    let message: String
    var onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(context.canEditRoom ? "Nothing listed yet" : "Nothing from \(context.room.name(of: .host)) yet",
                  systemImage: "bag")
                .font(.screenTitle)
                .foregroundStyle(Color.textPrimary)
        } description: {
            Group {
                if context.canEditRoom {
                    Text(message)
                } else {
                    Text("\(context.room.name(of: .host)) hasn’t added any things to this room yet. You’ll see them here as soon as they do.")
                }
            }
            .textRole(.secondary)
        } actions: {
            if context.canEditRoom {
                Button("Add by hand", action: onAdd).buttonStyle(.app(.primary, width: .hug))
            }
        }
    }
}

/// Shows the other person's latest change at the top of the screen for a few seconds:
/// a floating white card with a tinted icon circle.
struct ActivityBanner: ViewModifier {
    @Binding var event: ActivityEvent?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let event {
                HStack(spacing: Space.m) {
                    IconCircle(symbol: event.symbol, tone: event.status?.tone ?? .sage)
                    Text(event.text).font(.bodyStrong).foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Space.m)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .elevation(.floating)
                .padding(.horizontal, Space.page)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: event.id) {
                    UIAccessibility.post(notification: .announcement, argument: event.text)
                    try? await Task.sleep(for: Motion.bannerDuration)
                    withAnimation { self.event = nil }
                }
                .onTapGesture { withAnimation { self.event = nil } }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Dismisses")
            }
        }
        .animation(Motion.banner, value: event)
    }
}

extension View {
    func activityBanner(_ event: Binding<ActivityEvent?>) -> some View { modifier(ActivityBanner(event: event)) }
}

// MARK: - Bottom bar

/// The bottom bar: a white floating capsule; the selected item is the sage gradient tag.
struct AppTabBar<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String
        let symbol: String
        var badge = 0
        var id: Value { value }
    }

    let items: [Item]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(items) { item in
                let on = item.value == selection
                Button { selection = item.value } label: {
                    HStack(spacing: Space.s) {
                        Image(systemName: item.symbol)
                            .overlay(alignment: .topTrailing) {
                                if item.badge > 0 {
                                    Text("\(item.badge)")
                                        .font(.badge)
                                        .foregroundStyle(Color.onAccent)
                                        .padding(.horizontal, Space.xs)
                                        .frame(minWidth: Size.badgeSmall, minHeight: Size.badgeSmall)
                                        .background(Color.accent, in: Capsule())
                                        .offset(x: Space.m, y: -Space.s)
                                }
                            }
                        Text(item.title).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.button)
                    .foregroundStyle(on ? Tone.sage.text : Color.iconNeutral)
                    .frame(maxWidth: .infinity, minHeight: Size.control)
                    .background { if on { Capsule().fill(Tone.sage.fill) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(item.badge > 0 ? "\(item.title), \(item.badge) to do" : item.title)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(Space.xs)
        .background(Color.surface, in: Capsule())
        .elevation(.floating)
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.xs)
    }
}

// MARK: - Previews

#Preview("Tags and notes") {
    ScrollView {
        VStack(alignment: .leading, spacing: Space.l) {
            FlowLayout {
                AppTag(kind: .owner(.host), text: "Mine")
                AppTag(kind: .owner(.guest), text: "Sam’s")
                ForEach(ItemStatus.decisions, id: \.self) { AppTag(kind: .decision($0), text: $0.statusLabel) }
                AppTag(kind: .suggestion, text: "Sam: keep")
            }
            NoteBar(text: "Sam suggests: keep") { Button("Use it") {}.buttonStyle(.app(.primary, size: .compact)) }
            NoteBar(text: "1 placement needs a look", symbol: "exclamationmark.triangle", tone: .warning)
            KVRow(label: "Room code", value: "K7M2Q", valueFont: .codeSmall, tracking: Tracking.code) {
                Button("Copy") {}.buttonStyle(.app(.primary, size: .compact))
            }
            RoomCard(name: "Alex’s old room", plannedUse: "Study", status: "3 of 7 to decide", progress: 0.57)
            HStack { Avatar(name: "Linda", role: .host); Avatar(name: "Sam", role: .guest, online: true) }
            AppTabBar(items: [.init(value: 0, title: "Items", symbol: "list.bullet", badge: 3),
                              .init(value: 1, title: "Room plan", symbol: "cube")], selection: .constant(0))
        }
        .padding(Space.page)
    }
    .pageBackground()
}
