import SwiftUI

// Selection controls and inputs.

/// Selectable chip ("Guest room", "Box room 7′ 10″ × 9′ 2″").
struct AppChip: View {
    let title: String
    var detail: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Text(title)
                if let detail { Text(detail).foregroundStyle(isSelected ? Color.onAccent.opacity(Opacity.secondaryOnAccent) : Color.textTertiary) }
            }
            .font(.detail.weight(.medium))
            .padding(.horizontal, Space.l)
            .frame(minHeight: Size.tapTarget)
            .foregroundStyle(isSelected ? Color.onAccent : Color.textPrimary)
            .background(isSelected ? Color.accent : Color.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.outline, lineWidth: Stroke.regular))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A full-width choice with a tick ("Yes, there are items", "Just me").
struct PickRow: View {
    let title: String
    var subtitle: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title).font(isSelected ? .bodyStrong : .bodyText.weight(.medium))
                    if let subtitle { Text(subtitle).font(.detail).foregroundStyle(Color.textTertiary) }
                }
                Spacer(minLength: Space.s)
                TickBadge(isOn: isSelected)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
            .frame(minHeight: Size.control)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .strokeBorder(isSelected ? Color.accent : Color.outline, lineWidth: Stroke.regular))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Round tick: filled when on, an empty ring when off (selection never relies on colour alone).
struct TickBadge: View {
    var isOn: Bool
    var body: some View {
        Image(systemName: "checkmark")
            .font(.captionStrong)
            .foregroundStyle(isOn ? Color.onAccent : .clear)
            .frame(width: Size.tick, height: Size.tick)
            .background(isOn ? Color.accent : Color.clear, in: Circle())
            .overlay(Circle().strokeBorder(isOn ? Color.clear : Color.outlineStrong, lineWidth: Stroke.regular))
            .accessibilityHidden(true)
    }
}

/// Segmented switch whose labels can wrap (long names like "Waiting for Alex" don't get cut off).
struct SegmentedControl<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: String
        var count: Int?
        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: Space.xxs) {
            ForEach(segments) { segment in
                let on = segment.value == selection
                Button { withAnimation(Motion.standard) { selection = segment.value } } label: {
                    HStack(spacing: Space.xs) {
                        Text(segment.title)
                        if let count = segment.count, count > 0 {
                            Text("\(count)").foregroundStyle(Color.textTertiary)
                        }
                    }
                    .font(on ? .detailStrong : .detail.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, Space.xs)
                    .padding(.vertical, Space.xs)
                    .frame(maxWidth: .infinity, minHeight: Size.tapTarget)
                    .background(on ? Color.surface : Color.clear, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .elevation(.segment, on)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segment.count.map { "\(segment.title), \($0)" } ?? segment.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Space.xxs)
        .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

/// A row of options that scrolls sideways (plan versions): same look as SegmentedControl.
struct ScrollingSegments<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var badge: String?
        var badgeLabel: String?
        var id: Value { value }
    }

    let options: [Option]
    let selection: Value
    var onSelect: (Value) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xxs) {
                ForEach(options) { option in
                    let on = option.value == selection
                    Button { onSelect(option.value) } label: {
                        HStack(spacing: Space.xs) {
                            Text(option.title)
                            if let badge = option.badge {
                                Image(systemName: badge).imageScale(.small).accessibilityLabel(option.badgeLabel ?? "")
                            }
                        }
                        .font(on ? .detailStrong : .detail.weight(.medium))
                        .foregroundStyle(on ? Color.textPrimary : Color.textSecondary)
                        .padding(.horizontal, Space.m)
                        .frame(minHeight: Size.tapTarget)
                        .background(on ? Color.surface : .clear, in: RoundedRectangle(cornerRadius: Radius.s))
                        .elevation(.segment, on)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(Space.xxs)
            .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.control))
        }
    }
}

/// Tabs with an underline (catalogue categories).
struct UnderlineTabs<Value: Hashable>: View {
    let tabs: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xl) {
                ForEach(tabs, id: \.value) { tab in
                    let on = tab.value == selection
                    Button { selection = tab.value } label: {
                        Text(tab.title)
                            .font(on ? .detailStrong : .detail.weight(.medium))
                            .foregroundStyle(on ? Color.textPrimary : Color.textTertiary)
                            .frame(minHeight: Size.tapTarget)
                            .overlay(alignment: .bottom) {
                                if on { Rectangle().fill(Color.textPrimary).frame(height: Stroke.bold) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// − value + for a length, shown in the room's units.
struct LengthStepper: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let units: UnitSystem

    var body: some View {
        Stepper(value: $value, in: range, step: units.stepCm) {
            HStack {
                Text(label).font(.bodyStrong)
                Spacer()
                Text(units.roomLength(value)).monospacedDigit().foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityValue(units.roomLength(value))
        .padding(.horizontal, Space.l)
        .frame(minHeight: Size.control)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.m))
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
        HStack {
            Text("\(label) (\(units.inputUnit))").font(.bodyStrong)
            Spacer()
            TextField(label, value: Binding(get: { units.input(fromCm: value.wrappedValue) },
                                            set: { value.wrappedValue = units.cm(fromInput: Double($0)) }),
                      format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.app)
                .frame(maxWidth: Size.numberFieldMax)
                .accessibilityLabel("\(label) in \(units == .feet ? "inches" : "centimetres")")
        }
    }
}

/// Text field look: white, rounded, hairline border, 50 points tall.
struct AppTextFieldStyle: TextFieldStyle {
    enum Kind { case line, area }
    var kind: Kind = .line

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, kind == .area ? Space.m : Space.l)
            .padding(.vertical, kind == .area ? Space.m : 0)
            .frame(minHeight: Size.control)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Color.outlineStrong, lineWidth: Stroke.hairline))
    }
}

extension TextFieldStyle where Self == AppTextFieldStyle {
    static var app: AppTextFieldStyle { AppTextFieldStyle() }
    /// Multi-line notes and messages.
    static var appArea: AppTextFieldStyle { AppTextFieldStyle(kind: .area) }
}

/// Step dots at the top of the create flow.
struct ProgressSegments: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i <= current ? Color.accent : Color.outline).frame(height: Size.progressBar)
            }
        }
        .accessibilityHidden(true)
    }
}
