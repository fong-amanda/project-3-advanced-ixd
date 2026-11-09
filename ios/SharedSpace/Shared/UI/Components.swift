import SwiftUI

// Small building blocks shared across features, styled after the prototype.

// MARK: - Buttons

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, accent, soft }
    var kind: Kind = .primary
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 20)
            .frame(minHeight: 50)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .secondary ? Color.ssLine : .clear, lineWidth: 1.5))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .ssBg
        case .secondary, .soft: .ssInk
        case .accent: .ssAccentInk
        }
    }

    private var background: Color {
        switch kind {
        case .primary: .ssInk
        case .secondary: .ssSurface
        case .soft: .ssSurface2
        case .accent: .ssAccent
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ kind: PillButtonStyle.Kind, fullWidth: Bool = true) -> PillButtonStyle {
        PillButtonStyle(kind: kind, fullWidth: fullWidth)
    }
}

/// Selectable chip ("Home office", "Guest room", filters).
struct Chip: View {
    let title: String
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .foregroundStyle(isOn ? Color.ssBg : Color.ssInk)
                .background(isOn ? Color.ssInk : Color.ssSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? Color.ssInk : Color.ssLine, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Tags and avatars

struct Tag: View {
    let text: String
    var symbol: String?
    var foreground: Color = .ssInk2
    var background: Color = .ssSurface2

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
    }
}

struct Avatar: View {
    let name: String
    let role: Role
    /// nil = don't show presence; true/false = online dot / dimmed.
    var online: Bool?
    var size: CGFloat = 34

    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased())
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(role == .host ? Color.white : Color(hex: "#2B1D00"))
            .frame(width: size, height: size)
            .background(role.color, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                if online == true {
                    Circle().fill(Color(hex: "#43B06C"))
                        .frame(width: size * 0.32, height: size * 0.32)
                        .overlay(Circle().stroke(Color.ssBg, lineWidth: 2))
                }
            }
            .opacity(online == false ? 0.45 : 1)
            .accessibilityLabel(online == true ? "\(name), here now" : name)
    }
}

// MARK: - Cards and layout

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ssSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.ssLine))
    }
}

extension View {
    func ssCard(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

/// Wraps children onto new lines, like CSS flex-wrap. Used for chip groups.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

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
                let size = subviews[index].sizeThatFits(.unspecified)
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
            let size = view.sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - Items

/// Square thumbnail for an item: its photo when there is one, otherwise its category icon.
struct ItemThumb: View {
    let item: Item
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let image = photo {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: item.category.symbol)
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(Color(hex: item.category.colorHex))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.ssSurface2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }

    private var photo: UIImage? {
        guard item.photoPath != nil else { return nil }
        return UIImage(contentsOfFile: FileStore.itemPhotoURL(roomId: item.roomId, itemId: item.id).path())
    }
}

/// Coloured pill for an item's decision.
struct StatusTag: View {
    let item: Item
    let room: Room
    let me: Role

    var body: some View {
        Tag(text: SortRules.statusText(item, room: room, me: me), symbol: item.status.icon,
            foreground: item.status.color, background: item.status.softColor)
    }
}

/// Friendly "nothing here yet" state used by the Sort and Redesign tabs.
struct NoItemsYetView: View {
    let context: RoomContext
    let message: String
    @Environment(RoomSession.self) private var session

    var body: some View {
        ContentUnavailableView {
            Label("Nothing in this room yet", systemImage: "shippingbox")
        } description: {
            if context.canEditRoom {
                Text(message)
            } else {
                Text("\(context.room.name(of: .host)) hasn’t added any things to this room yet. You’ll see them here as soon as they do.")
            }
        } actions: {
            if context.canEditRoom {
                Button("Scan this room") { session.startScan() }
                    .buttonStyle(.pill(.primary, fullWidth: false))
                Button("Add items by hand") { session.showAddItem = true }
                    .buttonStyle(.pill(.secondary, fullWidth: false))
            }
        }
    }
}

// MARK: - Activity banner

/// Shows the other person's latest change at the top of the screen for a few seconds.
struct ActivityBanner: ViewModifier {
    @Binding var event: ActivityEvent?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let event {
                HStack(spacing: 10) {
                    Image(systemName: event.symbol)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(event.status?.color ?? .ssAccent, in: Circle())
                    Text(event.text).font(.subheadline.weight(.medium))
                }
                .foregroundStyle(Color.ssBg)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.ssInk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 12, y: 6)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: event.id) {
                    try? await Task.sleep(for: .seconds(3.6))
                    withAnimation { self.event = nil }
                }
                .onTapGesture { withAnimation { self.event = nil } }
            }
        }
        .animation(.spring(duration: 0.35), value: event)
    }
}

extension View {
    func activityBanner(_ event: Binding<ActivityEvent?>) -> some View { modifier(ActivityBanner(event: event)) }
}
