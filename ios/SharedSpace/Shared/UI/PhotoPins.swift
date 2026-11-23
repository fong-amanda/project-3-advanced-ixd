import SwiftUI

/// One numbered marker on a room photo.
struct PhotoPin: Identifiable, Equatable {
    let id: UUID
    let number: Int
    let label: String
    /// Fractions of the photo's width and height.
    var point: CGPoint
    var status: ItemStatus = .undecided
    /// Where it stands, in words ("going to Sam"); nil while listing things before the room exists.
    var statusText: String?
    var isSelected = false
    /// Checked while reviewing suggestions: confirmed (✓) or removed (✕, dimmed).
    var mark: Mark?
    /// What VoiceOver reads instead of "number, label, status".
    var spokenLabel: String?
    /// Draw the selected pin larger, so it stands out while its card is on screen.
    var growsWhenSelected = false

    enum Mark: Equatable { case confirmed, removed }
}

/// A room photo with numbered pins (the prototype's "photo + pins").
///
/// * Tap a pin to select it. Tap elsewhere to add something there (when `onTapPhoto` is set).
/// * Drag a pin to move it (when `onMovePin` is set). VoiceOver users get a "Move" action instead
///   of dragging: the item sheet lets them re-pin by tapping the photo.
struct PhotoWithPins: View {
    let image: UIImage
    let pins: [PhotoPin]
    var onTapPin: ((UUID) -> Void)?
    /// What tapping the photo does, for VoiceOver.
    var photoHint = "Double-tap to add something"
    var onTapPhoto: ((CGPoint) -> Void)?
    var onMovePin: ((UUID, CGPoint) -> Void)?
    /// Fill the frame (cropping) instead of showing the whole photo.
    var fill = false

    @State private var dragging: (id: UUID, point: CGPoint)?
    static let highlightScale: CGFloat = 1.3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let frame = imageFrame(in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .accessibilityLabel("Photo of the room")
                    .accessibilityHint(onTapPhoto == nil ? "" : photoHint)
                    .accessibilityAddTraits(onTapPhoto == nil ? [] : .isButton)
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard let onTapPhoto else { return }
                        let x = (value.location.x - frame.minX) / frame.width
                        let y = (value.location.y - frame.minY) / frame.height
                        guard (0...1).contains(x), (0...1).contains(y) else { return }
                        onTapPhoto(CGPoint(x: min(max(x, 0.03), 0.97), y: min(max(y, 0.03), 0.97)))
                    })
                let placed = Self.spreadApart(pins, in: frame, dragging: dragging)
                ForEach(pins) { pin in
                    let p = placed[pin.id] ?? .zero
                    marker(pin)
                        .position(p)
                        .zIndex(pin.isSelected ? 1 : 0)
                        .gesture(dragGesture(pin, frame: frame), including: onMovePin == nil ? .subviews : .all)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .aspectRatio(fill ? nil : image.size.width / max(image.size.height, 1), contentMode: .fit)
    }

    /// Where each pin is drawn, in view points. Pins closer than a tap target are nudged apart
    /// (only on screen; the saved position doesn't change) so their 44 × 44 areas don't overlap.
    /// The pin being dragged stays under the finger.
    static func spreadApart(_ pins: [PhotoPin], in frame: CGRect, dragging: (id: UUID, point: CGPoint)?) -> [UUID: CGPoint] {
        var points = pins.map { pin -> CGPoint in
            let p = dragging?.id == pin.id ? dragging!.point : pin.point
            return CGPoint(x: frame.minX + p.x * frame.width, y: frame.minY + p.y * frame.height)
        }
        let fixed = pins.map { $0.id == dragging?.id }
        let gap = Size.tapTarget
        let inset = frame.insetBy(dx: gap / 2, dy: gap / 2)
        for _ in 0..<12 {
            var moved = false
            for i in points.indices {
                for j in points.indices where j > i {
                    var dx = points[j].x - points[i].x, dy = points[j].y - points[i].y
                    // Pins exactly on top of each other: split them sideways.
                    if abs(dx) < 0.5 && abs(dy) < 0.5 { dx = 1; dy = 0 }
                    // Square tap areas overlap when both gaps are under a target's width.
                    guard abs(dx) < gap && abs(dy) < gap else { continue }
                    // Push along the axis that needs the smaller move.
                    let pushX = gap - abs(dx), pushY = gap - abs(dy)
                    let (mx, my): (CGFloat, CGFloat) = pushX <= pushY ? ((dx < 0 ? -1 : 1) * pushX, 0) : (0, (dy < 0 ? -1 : 1) * pushY)
                    let share: (CGFloat, CGFloat) = fixed[i] ? (0, 1) : fixed[j] ? (1, 0) : (0.5, 0.5)
                    points[i].x -= mx * share.0; points[i].y -= my * share.0
                    points[j].x += mx * share.1; points[j].y += my * share.1
                    moved = true
                }
            }
            for i in points.indices where !fixed[i] && inset.width > 0 && inset.height > 0 {
                points[i].x = min(max(points[i].x, inset.minX), inset.maxX)
                points[i].y = min(max(points[i].y, inset.minY), inset.maxY)
            }
            if !moved { break }
        }
        return Dictionary(uniqueKeysWithValues: zip(pins.map(\.id), points))
    }

    private func imageFrame(in size: CGSize) -> CGRect {
        let ar = image.size.width / max(image.size.height, 1)
        var w = size.width, h = size.width / ar
        if fill ? h < size.height : h > size.height { h = size.height; w = h * ar }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func marker(_ pin: PhotoPin) -> some View {
        Button { onTapPin?(pin.id) } label: {
            VStack(spacing: Space.xs) {
                NumberBadge(number: pin.number, isSelected: pin.isSelected, ring: ring(pin), placement: .onPhoto)
                    // The decision's symbol rides on the pin, so the ring colour is never the only cue.
                    .overlay(alignment: .bottomTrailing) { statusMark(pin) }
                    .scaleEffect(Motion.scale(Motion.dragScale, when: dragging?.id == pin.id, reduceMotion: reduceMotion))
                    // Larger while its card is showing. A size change, not motion: kept with Reduce Motion.
                    .scaleEffect(pin.isSelected && pin.growsWhenSelected ? Self.highlightScale : 1)
                    .opacity(pin.mark == .removed && !pin.isSelected ? Opacity.removedPin : 1)
                if pin.isSelected {
                    PhotoLabel(text: pin.statusText.map { "\(pin.label) · \($0.prefix(1).uppercased() + $0.dropFirst())" } ?? pin.label)
                }
            }
            // The badge is 30 points; the tap area is at least 44 × 44.
            .frame(minWidth: Size.tapTarget, minHeight: Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pin.spokenLabel ?? "\(pin.number), \(pin.label)\(pin.statusText.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(pin.isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer { Text("\(pin.number) · \(pin.label)") }
    }

    /// A small white-on-colour symbol for decided things (keep ✓, send 📦, let go ✕ …).
    @ViewBuilder private func statusMark(_ pin: PhotoPin) -> some View {
        if let mark = pin.mark {
            Image(systemName: mark == .confirmed ? "checkmark" : "xmark")
                .font(.caption2.weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.large)
                .foregroundStyle(Color.photoBadge)
                .frame(width: Size.badgeSmall - 2, height: Size.badgeSmall - 2)
                .background(mark == .confirmed ? Color.keep : Color.iconNeutral, in: Circle())
                .overlay(Circle().strokeBorder(Color.photoBadge, lineWidth: Stroke.hairline))
                .offset(x: Space.s, y: Space.s)
                .environment(\.colorScheme, .light)
                .accessibilityHidden(true)
        } else if pin.status != .undecided {
            Image(systemName: pin.status.icon)
                .font(.caption2.weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.large)
                .foregroundStyle(Color.photoBadge)
                .frame(width: Size.badgeSmall - 2, height: Size.badgeSmall - 2)
                .background(pin.status.color, in: Circle())
                .overlay(Circle().strokeBorder(Color.photoBadge, lineWidth: Stroke.hairline))
                .offset(x: Space.s, y: Space.s)
                .environment(\.colorScheme, .light)
                .accessibilityHidden(true)
        }
    }

    /// Ring colour shows the decision (with the symbol above); the selected pin also fills and
    /// shows its name and status.
    private func ring(_ pin: PhotoPin) -> Color {
        pin.isSelected ? .accent : (pin.status == .undecided ? .accent : pin.status.color)
    }

    private func dragGesture(_ pin: PhotoPin, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard onMovePin != nil else { return }
                let x = min(max((value.location.x - frame.minX) / frame.width, 0.02), 0.98)
                let y = min(max((value.location.y - frame.minY) / frame.height, 0.02), 0.98)
                dragging = (pin.id, CGPoint(x: x, y: y))
            }
            .onEnded { _ in
                if let d = dragging { onMovePin?(d.id, d.point) }
                dragging = nil
            }
    }
}
