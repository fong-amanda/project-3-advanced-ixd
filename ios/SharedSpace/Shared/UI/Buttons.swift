import SwiftUI

// Buttons. Screens pick a role, size, width and whether it's selected; they never restyle a button.

/// Every button in the app: a white capsule with a 1.5 pt outline. The colour lives in the label:
/// Sage for main actions, Deep brown for neutral ones, Brick for destructive ones. Selected, it
/// becomes the soft gradient tag in its colour with a thin matching outline. 52 pt tall (44 compact).
struct AppButtonStyle: ButtonStyle {
    enum Role: CaseIterable { case primary, neutral, destructive }
    enum Scale: CaseIterable { case regular, compact }
    enum Width { case fill, hug }

    var role: Role = .primary
    var size: Scale = .regular
    /// Defaults to full width for regular buttons and to the label's width for compact ones.
    var width: Width?
    var isSelected = false
    /// Gallery only: draw the pressed state.
    var previewPressed = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || previewPressed
        let fill = (width ?? (size == .regular ? .fill : .hug)) == .fill
        configuration.label
            .font(size == .compact ? .buttonCompact : .button)
            .multilineTextAlignment(.center)
            .padding(.horizontal, size == .compact ? Space.l : Space.xl)
            .padding(.vertical, Space.s)
            .frame(minHeight: size == .compact ? Size.tapTarget : Size.control)
            .frame(maxWidth: fill ? .infinity : nil)
            .foregroundStyle(isSelected ? role.tone.text : role.label)
            .background {
                if isSelected { Capsule().fill(role.tone.fill) } else { Capsule().fill(pressed ? Color.track : Color.surface) }
            }
            .overlay(Capsule().strokeBorder(isSelected ? role.tone.line : Color.outline, lineWidth: Stroke.regular))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : Opacity.disabled)
            .scaleEffect(pressed ? Motion.pressedScale : 1)
            .animation(Motion.quick, value: pressed)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension AppButtonStyle.Role {
    var label: Color {
        switch self {
        case .primary: .accent
        case .neutral: .iconNeutral
        case .destructive: .danger
        }
    }

    var tone: Tone {
        switch self {
        case .primary: .sage
        case .neutral: .brown
        case .destructive: .brick
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var app: AppButtonStyle { AppButtonStyle() }
    static func app(_ role: AppButtonStyle.Role, size: AppButtonStyle.Scale = .regular,
                    width: AppButtonStyle.Width? = nil, selected: Bool = false) -> AppButtonStyle {
        AppButtonStyle(role: role, size: size, width: width, isSelected: selected)
    }
}

/// An icon-only button: 44-point target and a spoken label. `filled` draws the white outlined circle.
struct IconButton: View {
    let symbol: String
    let label: String
    var role: AppButtonStyle.Role = .neutral
    var filled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.button)
                .frame(width: Size.tapTarget, height: Size.tapTarget)
                .background { if filled { Circle().fill(Color.surface) } }
                .overlay { if filled { Circle().strokeBorder(Color.outline, lineWidth: Stroke.regular) } }
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(role.label)
        .accessibilityLabel(label)
    }
}

/// Back: a 48-point white circle with a Deep brown chevron.
struct BackButton: View {
    var label = "Back"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.button)
                .foregroundStyle(Color.iconNeutral)
                .frame(width: Size.backButton, height: Size.backButton)
                .background(Circle().fill(Color.surface))
                .overlay(Circle().strokeBorder(Color.outline, lineWidth: Stroke.regular))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Toolbar icon (system styling, 44-point target).
struct ToolbarIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(Color.iconNeutral)
            .frame(minWidth: Size.tapTarget, minHeight: Size.tapTarget)
    }
}

/// The screen's one main action, bottom right: a white capsule with a Sage circle and a label.
/// Lists under it add `Size.floatingClearance` of bottom padding so they scroll clear.
struct FloatingActionButton: View {
    let title: String
    var symbol = "plus"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: symbol)
                    .font(.button)
                    .foregroundStyle(Color.onAccent)
                    .frame(width: Size.floatingButtonIcon, height: Size.floatingButtonIcon)
                    .background(Circle().fill(Color.accent))
                    .accessibilityHidden(true)
                Text(title).font(.button).foregroundStyle(Color.textPrimary)
            }
            .padding(.leading, Space.s)
            .padding(.trailing, Space.xl)
            .frame(minHeight: Size.floatingButton)
            .background(Capsule().fill(Color.surface))
            .contentShape(Capsule())
            .elevation(.floating)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Places a floating action button bottom right, 20 points from the edge, over scrolling content.
extension View {
    func floatingAction(_ title: String, symbol: String = "plus", action: @escaping () -> Void) -> some View {
        overlay(alignment: .bottomTrailing) {
            FloatingActionButton(title: title, symbol: symbol, action: action)
                .padding(Space.xl)
        }
    }
}

/// Shrinks slightly while pressed. For controls that draw their own look.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Motion.pressedScale : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

// MARK: - Decisions

/// One decision. `.full` is the one-at-a-time choice: a full-width button with a 40-point tinted
/// icon circle and the label on one line. `.compact` is a small capsule that sits beside the others.
/// Selected, it becomes the decision's gradient with a thin outline and a checkmark at the end, so
/// the choice never relies on colour alone.
struct DecisionButton: View {
    enum Layout: CaseIterable { case full, compact }

    let decision: ItemStatus
    var title: String?
    var detail: String?
    var isSelected = false
    var layout: Layout = .compact
    /// Suggesting for someone else (read out as "Suggest: …").
    var suggesting = false
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            switch layout {
            case .full: full
            case .compact: compact
            }
        }
        .buttonStyle(PressableStyle())
        .opacity(isEnabled ? 1 : Opacity.disabled)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(suggesting ? "Suggest: \(resolvedTitle)" : resolvedTitle)
        .accessibilityHint(detail ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var resolvedTitle: String { title ?? (layout == .full ? decision.label : decision.shortLabel) }
    private var tone: Tone { decision.tone }

    private var compact: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: decision.icon).foregroundStyle(isSelected ? tone.text : tone.icon).accessibilityHidden(true)
            Text(resolvedTitle)
            if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
        }
        .font(.buttonCompact)
        .foregroundStyle(isSelected ? tone.text : Color.textPrimary)
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .frame(minHeight: Size.tapTarget)
        .background { selectable(Capsule()) }
        .contentShape(Capsule())
    }

    private var full: some View {
        HStack(spacing: Space.m) {
            Image(systemName: decision.icon)
                .font(.button)
                .foregroundStyle(tone.icon)
                .frame(width: Size.iconCircle, height: Size.iconCircle)
                .background(Circle().fill(isSelected ? Color.surface : tone.tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(resolvedTitle).font(.button)
                if let detail { Text(detail).font(.detail).foregroundStyle(isSelected ? tone.text : Color.textSecondary) }
            }
            .foregroundStyle(isSelected ? tone.text : Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected { Image(systemName: "checkmark").font(.button).foregroundStyle(tone.text).accessibilityHidden(true) }
        }
        .padding(.leading, Space.s)
        .padding(.trailing, Space.xl)
        .padding(.vertical, Space.s)
        .frame(minHeight: Size.control + Space.s)
        .background { selectable(Capsule()) }
        .contentShape(Capsule())
    }

    @ViewBuilder private func selectable<S: InsettableShape>(_ shape: S) -> some View {
        if isSelected {
            shape.fill(tone.fill).overlay(shape.strokeBorder(tone.line, lineWidth: Stroke.regular))
        } else {
            shape.fill(Color.surface).overlay(shape.strokeBorder(Color.outline, lineWidth: Stroke.regular))
        }
    }
}

// MARK: - Previews

#Preview("Buttons") {
    VStack(spacing: Space.m) {
        ForEach(AppButtonStyle.Role.allCases, id: \.self) { role in
            HStack {
                Button("\(String(describing: role).capitalized)") {}.buttonStyle(.app(role))
                Button("Pressed") {}.buttonStyle(AppButtonStyle(role: role, previewPressed: true))
                Button("Selected") {}.buttonStyle(.app(role, selected: true))
            }
        }
        Button("Disabled") {}.buttonStyle(.app).disabled(true)
        HStack { BackButton {}; IconButton(symbol: "trash", label: "Remove", role: .destructive, filled: true) {} }
        FloatingActionButton(title: "New room") {}
    }
    .padding(Space.page)
    .pageBackground()
}

#Preview("Decisions") {
    VStack(spacing: Space.s) {
        ForEach(ItemStatus.decisions, id: \.self) { DecisionButton(decision: $0, isSelected: $0 == .keep, layout: .full) {} }
        FlowLayout {
            ForEach(ItemStatus.decisions, id: \.self) { DecisionButton(decision: $0, isSelected: $0 == .sendToOwner) {} }
        }
    }
    .padding(Space.page)
    .pageBackground()
}

extension ToolbarContent {
    /// Drops the system's glass capsule behind a toolbar item that draws its own look (BackButton).
    @ToolbarContentBuilder func plainToolbarBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
