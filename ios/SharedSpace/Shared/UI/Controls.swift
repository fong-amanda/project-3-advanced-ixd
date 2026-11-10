import SwiftUI

// Selection controls and inputs.

/// A chip ("Guest room", "Box room 7′ 10″ × 9′ 2″"): a default button that becomes the gradient
/// tag when selected. Chips sit in scrolling rows (see ChipPicker) or wrap (FlowLayout).
struct AppChip: View {
    let title: String
    var detail: String?
    var symbol: String?
    var isSelected: Bool
    var tone: Tone = .sage
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(title)
                if let detail { Text(detail).font(.detail).foregroundStyle(isSelected ? tone.text : Color.textSecondary) }
            }
        }
        .buttonStyle(AppChipStyle(isSelected: isSelected, tone: tone))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct AppChipStyle: ButtonStyle {
    var isSelected: Bool
    var tone: Tone = .sage
    /// Gallery only.
    var previewPressed = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || previewPressed
        configuration.label
            .font(.buttonCompact)
            .foregroundStyle(isSelected ? tone.text : Color.textPrimary)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
            .frame(minHeight: Size.tapTarget)
            .background {
                if isSelected { Capsule().fill(tone.fill) } else { Capsule().fill(pressed ? Color.track : Color.surface) }
            }
            .overlay(Capsule().strokeBorder(isSelected ? tone.line : Color.outline, lineWidth: Stroke.regular))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : Opacity.disabled)
    }
}

/// One option in a ChipPicker.
struct ChipOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var count: Int?
    var symbol: String?
    /// Spoken with the symbol ("Looks good to Alex").
    var symbolLabel: String?
    var id: Value { value }
}

/// Pick one of several options as a scrolling row of chips. Used for filters, views, versions,
/// categories and options, instead of segmented controls or underlined tabs.
struct ChipPicker<Value: Hashable>: View {
    let options: [ChipOption<Value>]
    @Binding var selection: Value
    var accessibilityLabel = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(options) { option in
                    let on = option.value == selection
                    Button { withAnimation(Motion.standard) { selection = option.value } } label: {
                        HStack(spacing: Space.xs) {
                            Text(option.title)
                            if let count = option.count, count > 0 {
                                Text("\(count)").foregroundStyle(on ? Tone.sage.text : Color.textSecondary)
                            }
                            if let symbol = option.symbol {
                                Image(systemName: symbol).accessibilityLabel(option.symbolLabel ?? "")
                            }
                        }
                    }
                    .buttonStyle(AppChipStyle(isSelected: on))
                    .accessibilityLabel(option.count.map { "\(option.title), \($0)" } ?? option.title)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, Stroke.regular)   // room for the outlines
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A full-width choice with a tick ("Yes, there are items", "Just me"). Selected: the sage
/// gradient with a thin outline and a filled tick.
struct PickRow: View {
    let title: String
    var subtitle: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title).font(.bodyStrong).foregroundStyle(isSelected ? Tone.sage.text : Color.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(.detail).foregroundStyle(isSelected ? Tone.sage.text : Color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TickBadge(isOn: isSelected)
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.m)
            .frame(minHeight: Size.control)
            .background {
                let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                if isSelected {
                    shape.fill(Tone.sage.fill).overlay(shape.strokeBorder(Tone.sage.line, lineWidth: Stroke.regular))
                } else {
                    shape.fill(Color.surface).overlay(shape.strokeBorder(Color.outline, lineWidth: Stroke.regular))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Round tick: filled Sage when on, an empty ring when off (selection never relies on colour alone).
struct TickBadge: View {
    var isOn: Bool
    var body: some View {
        Image(systemName: "checkmark")
            .font(.badge)
            .foregroundStyle(isOn ? Color.onAccent : .clear)
            .frame(width: Size.tick, height: Size.tick)
            .background(isOn ? Color.accent : Color.clear, in: Circle())
            .overlay(Circle().strokeBorder(isOn ? Color.clear : Color.outlineStrong, lineWidth: Stroke.regular))
            .accessibilityHidden(true)
    }
}

// MARK: - Switch

/// On: Sage track, white knob. Off: Cloud track with a Deep brown outline and knob.
struct AppToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { withAnimation(Motion.standard) { configuration.isOn.toggle() } } label: {
            HStack(spacing: Space.m) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                let knob = Size.switchTrack.height - Size.switchKnobInset * 2
                Capsule()
                    .fill(configuration.isOn ? Color.accent : Color.track)
                    .overlay(Capsule().strokeBorder(configuration.isOn ? Color.clear : Color.iconNeutral, lineWidth: Stroke.regular))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(configuration.isOn ? Color.onAccent : Color.iconNeutral)
                            .frame(width: knob, height: knob)
                            .padding(Size.switchKnobInset)
                    }
                    .frame(width: Size.switchTrack.width, height: Size.switchTrack.height)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

extension ToggleStyle where Self == AppToggleStyle {
    static var app: AppToggleStyle { AppToggleStyle() }
}

/// A switch on a card, with a title and an optional explanation ("I measured the room").
struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.bodyStrong).foregroundStyle(Color.textPrimary)
                if let subtitle { Text(subtitle).textRole(.secondary) }
            }
        }
        .toggleStyle(.app)
        .card(padding: Space.l, radius: Radius.tile)
    }
}

// MARK: - Numbers

/// − value + for a length, shown in the room's units.
struct LengthStepper: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let units: UnitSystem

    var body: some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(label).font(.bodyStrong).foregroundStyle(Color.textPrimary)
                Text(units.roomLength(value)).font(.detail).monospacedDigit().foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(symbol: "minus", label: "Less", filled: true) { value = max(range.lowerBound, value - units.stepCm) }
                .disabled(value <= range.lowerBound)
            IconButton(symbol: "plus", label: "More", filled: true) { value = min(range.upperBound, value + units.stepCm) }
                .disabled(value >= range.upperBound)
        }
        .padding(.vertical, Space.s)
        .padding(.leading, Space.xl)
        .padding(.trailing, Space.s)
        .card(padding: 0, radius: Radius.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(units.roomLength(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + units.stepCm)
            case .decrement: value = max(range.lowerBound, value - units.stepCm)
            @unknown default: break
            }
        }
    }
}

/// Width / depth / height typed in inches or cm, stored in cm.
struct DimensionFields: View {
    let units: UnitSystem
    @Binding var w: Double
    @Binding var d: Double
    @Binding var h: Double

    var body: some View {
        VStack(spacing: Space.s) {
            field("Width", $w)
            field("Depth", $d)
            field("Height", $h)
        }
    }

    private func field(_ label: String, _ value: Binding<Double>) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("\(label) (\(units.inputUnit))").font(.bodyStrong)
                Spacer()
                input(label, value).frame(maxWidth: Size.numberFieldMax)
            }
            VStack(alignment: .leading, spacing: Space.s) {
                Text("\(label) (\(units.inputUnit))").font(.bodyStrong)
                input(label, value)
            }
        }
        .foregroundStyle(Color.textPrimary)
    }

    private func input(_ label: String, _ value: Binding<Double>) -> some View {
        TextField(label, value: Binding(get: { units.input(fromCm: value.wrappedValue) },
                                        set: { value.wrappedValue = units.cm(fromInput: Double($0)) }),
                  format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.app)
            .accessibilityLabel("\(label) in \(units == .feet ? "inches" : "centimetres")")
    }
}

/// Text field look: white, rounded, a visible outline, 52 points tall.
struct AppTextFieldStyle: TextFieldStyle {
    enum Kind { case line, area }
    var kind: Kind = .line

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.bodyText)
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Space.l)
            .padding(.vertical, kind == .area ? Space.m : Space.xs)
            .frame(minHeight: Size.control)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .strokeBorder(Color.outlineStrong, lineWidth: Stroke.regular))
    }
}

extension TextFieldStyle where Self == AppTextFieldStyle {
    static var app: AppTextFieldStyle { AppTextFieldStyle() }
    /// Multi-line notes and messages.
    static var appArea: AppTextFieldStyle { AppTextFieldStyle(kind: .area) }
}

// MARK: - Progress

/// Rounded progress bar: Sage fill on a Cloud track (a darker track on Mist cards).
struct ProgressBar: View {
    /// 0...1.
    let value: Double
    @Environment(\.onWhiteSurface) private var onWhite

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(onWhite ? Color.trackOnMuted : Color.track)
                Capsule().fill(Color.accent)
                    .frame(width: max(value > 0 ? Size.progressBar : 0, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: Size.progressBar)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent")
    }
}

/// Step bars at the top of the create flow.
struct ProgressSegments: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i <= current ? Color.accent : Color.track).frame(height: Size.progressBar)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Selection") {
    @Previewable @State var pick = 0
    @Previewable @State var on = true
    @Previewable @State var length = 340.0
    ScrollView {
        VStack(alignment: .leading, spacing: Space.l) {
            ChipPicker(options: [.init(value: 0, title: "For you to decide", count: 3), .init(value: 1, title: "Waiting for Alex", count: 4),
                                 .init(value: 2, title: "Decided")], selection: $pick)
            HStack { AppChip(title: "Study", isSelected: true) {}; AppChip(title: "Guest room", isSelected: false) {} }
            AppChip(title: "Disabled", isSelected: false) {}.disabled(true)
            PickRow(title: "Yes, there are items", isSelected: true) {}
            PickRow(title: "No, the room is empty", subtitle: "You can add things later", isSelected: false) {}
            ToggleRow(title: "I measured the room", subtitle: "Turns on fit checks", isOn: $on)
            LengthStepper(label: "Width", value: $length, range: 150...800, units: .feet)
            TextField("Room name", text: .constant("Alex’s old room")).textFieldStyle(.app)
            ProgressBar(value: 0.4)
            ProgressSegments(count: 4, current: 1)
        }
        .padding(Space.page)
    }
    .pageBackground()
}
