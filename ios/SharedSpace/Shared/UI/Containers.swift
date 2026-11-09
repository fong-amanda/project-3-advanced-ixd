import SwiftUI

// Tags, text roles, cards, notes and layout helpers.

// MARK: - Text roles

/// How a piece of text is used. Sets both font and colour from Theme.
enum TextRole: CaseIterable {
    case screenTitle, sectionTitle, cardTitle, body, bodyStrong, label, secondary, hint, error

    var font: Font {
        switch self {
        case .screenTitle: .screenTitle
        case .sectionTitle: .sectionTitle
        case .cardTitle: .cardTitle
        case .body: .bodyText
        case .bodyStrong: .bodyStrong
        case .label, .error: .detailStrong
        case .secondary: .detail
        case .hint: .footnoteText
        }
    }

    var color: Color {
        switch self {
        case .secondary, .hint: .textTertiary
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

// MARK: - Tags

/// Small rounded label. The kind sets the colours; decisions also get their icon.
struct AppTag: View {
    enum Kind: Equatable {
        case neutral, highlight, suggestion
        case decision(ItemStatus)
        case owner(Role)
        case fit(Fit)
    }

    let kind: Kind
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: Space.xs) {
            if let icon = symbol ?? defaultSymbol { Image(systemName: icon).imageScale(.small).accessibilityHidden(true) }
            Text(text)
        }
        .font(.captionStrong)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .foregroundStyle(colors.fg)
        .background(colors.bg, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
    }

    private var defaultSymbol: String? {
        switch kind {
        case .decision(let s): s.icon
        case .suggestion: "text.bubble"
        case .fit(let f): f == .no ? "xmark" : "checkmark"
        default: nil
        }
    }

    private var colors: (fg: Color, bg: Color) {
        switch kind {
        case .neutral: (.textSecondary, .surfaceMuted)
        case .highlight: (.onHighlight, .highlightSoft)
        case .suggestion: (.onAccentSoft, .accentSoft)
        case .decision(let s): (s.color, s.softColor)
        case .owner(let r): (.textPrimary, r.softColor)
        case .fit(.ok): (.success, .successSoft)
        case .fit(.tight): (.warning, .warningSoft)
        case .fit(.no): (.danger, .dangerSoft)
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
            .font(.captionStrong)
            .foregroundStyle(isSelected ? Color.onAccent : (placement == .onPhoto ? Color.onPhotoText : Color.textPrimary))
            .frame(minWidth: size, minHeight: size)
            .background(isSelected ? Color.accent : (placement == .onPhoto ? Color.photoBadge : Color.surface), in: Circle())
            .overlay(Circle().strokeBorder(isSelected ? Color.accent : ring, lineWidth: size >= Size.pin ? Stroke.bold : Stroke.hairline))
            .elevation(.segment, placement == .onPhoto)
    }
}

/// The name shown under a selected pin on a photo.
struct PhotoLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.captionStrong)
            .foregroundStyle(Color.photoBadge)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xxs)
            .background(Color.onPhotoText.opacity(Opacity.pinLabel), in: RoundedRectangle(cornerRadius: Radius.xs))
            .fixedSize()
    }
}

// MARK: - Containers

enum CardStyle { case plain, outlined, raised }

extension View {
    /// A white card. `.outlined` has a hairline, `.raised` a soft shadow.
    func card(_ style: CardStyle = .outlined, padding: CGFloat = Space.l, radius: CGFloat = Radius.m) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(style == .outlined ? Color.outline : .clear))
            .elevation(.card, style == .raised)
    }

    /// A rounded group of rows (no inner padding; rows bring their own).
    func listGroup() -> some View {
        self.background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Color.outline))
            .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }

    /// Page content padding.
    func pagePadding() -> some View { padding(.horizontal, Space.l).padding(.vertical, Space.m) }

    /// The look behind photos and plans.
    func stage(_ fill: Color = .stage) -> some View {
        frame(maxWidth: .infinity)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }
}

/// A 1-point line in the outline colour (works inside any stack, unlike Divider in overlays).
struct Hairline: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle().fill(Color.outline).frame(height: Stroke.hairline).padding(.leading, inset)
    }
}

/// A message bar with an optional action. `.info` is sage, `.warning` amber.
struct NoteBar<Accessory: View>: View {
    enum Tone: CaseIterable { case info, warning }
    let text: String
    var symbol = "text.bubble"
    var tone: Tone = .info
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(text).font(.detail)
            Spacer(minLength: Space.s)
            accessory.font(.detailStrong).frame(minHeight: Size.tapTarget)
        }
        .foregroundStyle(tone == .info ? Color.onAccentSoft : Color.warning)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, minHeight: Size.tapTarget, alignment: .leading)
        .background(tone == .info ? Color.accentSoft : Color.warningSoft,
                    in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }
}

extension NoteBar where Accessory == EmptyView {
    init(text: String, symbol: String = "text.bubble", tone: Tone = .info) {
        self.init(text: text, symbol: symbol, tone: tone) { EmptyView() }
    }
}

/// "Room code   K7M2Q   Copy" — a label, a value and an optional action between hairlines.
struct KVRow<Accessory: View>: View {
    let label: String
    let value: String
    var valueFont: Font = .bodyStrong
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: Space.m) {
            Text(label).foregroundStyle(Color.textTertiary)
            Text(value).font(valueFont).foregroundStyle(Color.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .padding(.vertical, Space.s)
        .frame(minHeight: Size.tapTarget)
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
    }
}

/// The ">" at the end of a tappable row.
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.captionText).foregroundStyle(Color.textTertiary).accessibilityHidden(true)
    }
}

/// Small bold heading above a group ("Your decision", "Belongs to").
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).textRole(.label).accessibilityAddTraits(.isHeader)
    }
}

/// A big tappable choice ("Take a photo", "Scan with LiDAR").
struct ChoiceTile: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentText).accessibilityHidden(true)
            Text(title).textRole(.bodyStrong)
            Text(detail).textRole(.secondary)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, minHeight: Size.row * 2, alignment: .topLeading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Color.outline, lineWidth: Stroke.regular))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Wraps children onto new lines, like CSS flex-wrap. Used for chip groups.
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

struct Avatar: View {
    let name: String
    let role: Role
    /// nil = don't show presence; true/false = online dot / dimmed.
    var online: Bool?
    var size: CGFloat = Size.avatar

    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased())
            .font(.glyph(fitting: size, weight: .bold))
            .foregroundStyle(role.onColor)
            .frame(width: size, height: size)
            .background(role.color, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                if online == true {
                    Circle().fill(Color.online)
                        .frame(width: size * 0.32, height: size * 0.32)
                        .overlay(Circle().stroke(Color.pageBackground, lineWidth: Stroke.bold))
                }
            }
            .opacity(online == false ? Opacity.offline : 1)
            .accessibilityLabel(online == true ? "\(name), here now" : name)
    }
}

/// The two overlapping squares from the prototype's logo. Drawn on a 32-unit grid.
struct BrandMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 32
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4 * s).fill(Color.logoPrimary)
                    .frame(width: 16 * s, height: 16 * s).offset(x: 3 * s, y: 7 * s)
                RoundedRectangle(cornerRadius: 4 * s).fill(Color.logoSecondary)
                    .frame(width: 16 * s, height: 16 * s).offset(x: 13 * s, y: 11 * s)
                Rectangle().fill(Color.logoOverlap.opacity(0.55))
                    .frame(width: 6 * s, height: 12 * s).offset(x: 13 * s, y: 11 * s)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Room card

/// A room on the home screen: its photo, name, planned use, and a status pill.
struct RoomCard: View {
    enum Tint: CaseIterable { case highlight, accent, neutral }

    let name: String
    let plannedUse: String
    let status: String
    var image: UIImage?
    var tint: Tint = .highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.stage
                        Image(systemName: "photo").font(.glyph(.medium)).foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .frame(height: Size.roomCardImage)
            .frame(maxWidth: .infinity)
            .clipped()
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(name).textRole(.cardTitle)
                if !plannedUse.isEmpty {
                    HStack(spacing: Space.s) {
                        Text("Planned use").foregroundStyle(Color.textTertiary)
                        Text(plannedUse).fontWeight(.semibold).foregroundStyle(Color.textPrimary)
                    }
                    .font(.detail)
                }
                Text(status)
                    .font(.detailStrong)
                    .foregroundStyle(pill.fg)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.xs)
                    .background(pill.bg, in: Capsule())
                    .padding(.top, Space.s)
            }
            .padding(Space.l)
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .elevation(.card)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var pill: (fg: Color, bg: Color) {
        switch tint {
        case .highlight: (.onHighlight, .highlightSoft)
        case .accent: (.onAccentSoft, .accentSoft)
        case .neutral: (.textSecondary, .surfaceMuted)
        }
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
        } description: {
            if context.canEditRoom {
                Text(message)
            } else {
                Text("\(context.room.name(of: .host)) hasn’t added any things to this room yet. You’ll see them here as soon as they do.")
            }
        } actions: {
            if context.canEditRoom {
                Button("Add by hand", action: onAdd).buttonStyle(.app(.primary, width: .hug))
            }
        }
    }
}

/// Shows the other person's latest change at the top of the screen for a few seconds.
struct ActivityBanner: ViewModifier {
    @Binding var event: ActivityEvent?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let event {
                HStack(spacing: Space.s) {
                    Image(systemName: event.symbol)
                        .foregroundStyle(Color.onAccent)
                        .frame(width: Size.tick, height: Size.tick)
                        .background(event.status?.color ?? .accent, in: Circle())
                        .accessibilityHidden(true)
                    Text(event.text).font(.detail.weight(.medium))
                }
                .foregroundStyle(Color.pageBackground)
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
                .background(Color.textPrimary, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                .elevation(.floating)
                .padding(.horizontal, Space.l)
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
