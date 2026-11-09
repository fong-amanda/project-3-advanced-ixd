import SwiftUI

/// One numbered marker on a room photo.
struct PhotoPin: Identifiable, Equatable {
    let id: UUID
    let number: Int
    let label: String
    /// Fractions of the photo's width and height.
    var point: CGPoint
    var status: ItemStatus = .undecided
    var isSelected = false
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
    var onTapPhoto: ((CGPoint) -> Void)?
    var onMovePin: ((UUID, CGPoint) -> Void)?
    /// Fill the frame (cropping) instead of showing the whole photo.
    var fill = false

    @State private var dragging: (id: UUID, point: CGPoint)?

    var body: some View {
        GeometryReader { geo in
            let frame = imageFrame(in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .accessibilityLabel("Photo of the room")
                    .accessibilityHint(onTapPhoto == nil ? "" : "Double-tap to add something")
                    .accessibilityAddTraits(onTapPhoto == nil ? [] : .isButton)
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard let onTapPhoto else { return }
                        let x = (value.location.x - frame.minX) / frame.width
                        let y = (value.location.y - frame.minY) / frame.height
                        guard (0...1).contains(x), (0...1).contains(y) else { return }
                        onTapPhoto(CGPoint(x: min(max(x, 0.03), 0.97), y: min(max(y, 0.03), 0.97)))
                    })
                ForEach(pins) { pin in
                    let p = dragging?.id == pin.id ? dragging!.point : pin.point
                    marker(pin)
                        .position(x: frame.minX + p.x * frame.width, y: frame.minY + p.y * frame.height)
                        .gesture(dragGesture(pin, frame: frame), including: onMovePin == nil ? .subviews : .all)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .aspectRatio(fill ? nil : image.size.width / max(image.size.height, 1), contentMode: .fit)
    }

    private func imageFrame(in size: CGSize) -> CGRect {
        let ar = image.size.width / max(image.size.height, 1)
        var w = size.width, h = size.width / ar
        if fill ? h < size.height : h > size.height { h = size.height; w = h * ar }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func marker(_ pin: PhotoPin) -> some View {
        Button { onTapPin?(pin.id) } label: {
            VStack(spacing: Space.xxs) {
                NumberBadge(number: pin.number, isSelected: pin.isSelected, ring: ring(pin), placement: .onPhoto)
                    .scaleEffect(dragging?.id == pin.id ? Motion.dragScale : 1)
                if pin.isSelected { PhotoLabel(text: pin.label) }
            }
            .frame(minWidth: Size.tapTarget, minHeight: Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(pin.number), \(pin.label)")
        .accessibilityValue(pin.status == .undecided ? "" : pin.status.statusLabel)
        .accessibilityAddTraits(pin.isSelected ? .isSelected : [])
    }

    /// Ring colour shows the decision; the selected pin also fills and shows its name.
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
