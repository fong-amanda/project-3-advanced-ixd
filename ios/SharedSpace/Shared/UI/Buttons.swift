import SwiftUI

// Buttons. Screens pick a role, size and width; they never restyle a button.

/// The app's buttons: capsules, 50 points tall (44 when compact). Text always carries the meaning.
struct AppButtonStyle: ButtonStyle {
    enum Role: CaseIterable { case primary, neutral, quiet, highlight, destructive }
    enum Scale: CaseIterable { case regular, compact }
    enum Width { case fill, hug }

    var role: Role = .primary
    var size: Scale = .regular
    var width: Width = .fill
    /// Gallery only: draw the pressed state.
    var previewPressed = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || previewPressed
        configuration.label
            .font(size == .compact ? .detailStrong : .bodyStrong)
            .multilineTextAlignment(.center)
            .padding(.horizontal, size == .compact ? Space.l : Space.xl)
            .padding(.vertical, Space.xs)
            .frame(minHeight: size == .compact ? Size.tapTarget : Size.control)
            .frame(maxWidth: width == .fill ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(role == .neutral ? Color.outline : .clear, lineWidth: Stroke.regular))
            .contentShape(Capsule())
            .opacity(isEnabled ? (pressed ? Opacity.pressed : 1) : Opacity.disabled)
            .scaleEffect(pressed ? Motion.pressedScale : 1)
            .animation(Motion.quick, value: pressed)
    }

    private var foreground: Color {
        switch role {
        case .primary: .onAccent
        case .neutral, .quiet: .textPrimary
        case .highlight: .onHighlight
        case .destructive: .danger
        }
    }

    private var background: Color {
        switch role {
        case .primary: .accent
        case .neutral: .surface
        case .quiet: .surfaceMuted
        case .highlight: .highlight
        case .destructive: .dangerSoft
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var app: AppButtonStyle { AppButtonStyle() }
    static func app(_ role: AppButtonStyle.Role, size: AppButtonStyle.Scale = .regular,
                    width: AppButtonStyle.Width = .fill) -> AppButtonStyle {
        AppButtonStyle(role: role, size: size, width: width)
    }
}

/// A quiet text action ("+ Add something", "Copy"), 44 points tall.
struct LinkButtonStyle: ButtonStyle {
    enum Role: CaseIterable { case accent, destructive, onTint }
    var role: Role = .accent
    var previewPressed = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || previewPressed
        configuration.label
            .font(.detailStrong)
            .foregroundStyle(color)
            .frame(minHeight: Size.tapTarget)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (pressed ? Opacity.linkPressed : 1) : Opacity.disabled)
    }

    private var color: Color {
        switch role {
        case .accent: .accentText
        case .destructive: .danger
        case .onTint: .onAccentSoft
        }
    }
}

extension ButtonStyle where Self == LinkButtonStyle {
    static var link: LinkButtonStyle { LinkButtonStyle() }
    static func link(_ role: LinkButtonStyle.Role) -> LinkButtonStyle { LinkButtonStyle(role: role) }
}

/// An icon-only button with a 44-point target and a spoken label.
struct IconButton: View {
    let symbol: String
    let label: String
    var role: LinkButtonStyle.Role = .accent
    var filled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: Size.tapTarget, height: Size.tapTarget)
                .background(filled ? Color.surfaceMuted : .clear, in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.danger : (filled ? Color.textPrimary : Color.accentText))
        .accessibilityLabel(label)
    }
}

/// Toolbar icon (system styling, 44-point target).
struct ToolbarIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).frame(minWidth: Size.tapTarget, minHeight: Size.tapTarget)
    }
}

// MARK: - Decisions

/// One decision. `.full` is the one-at-a-time card choice (icon tile, title, explanation);
/// `.compact` is a row in the item sheet. Selected fills with the accent and gets a tick, so the
/// choice never relies on colour alone.
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

    var body: some View {
        Button(action: action) {
            switch layout {
            case .full: full
            case .compact: compact
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(suggesting ? "Suggest: \(resolvedTitle)" : resolvedTitle)
        .accessibilityHint(detail ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var resolvedTitle: String { title ?? (layout == .full ? decision.label : decision.shortLabel) }

    private var compact: some View {
        HStack(spacing: Space.s) {
            Image(systemName: decision.icon).frame(width: Size.tick).accessibilityHidden(true)
            Text(resolvedTitle).frame(maxWidth: .infinity, alignment: .leading)
            if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
        }
        .font(.bodyStrong)
        .padding(.horizontal, Space.l)
        .frame(minHeight: Size.control)
        .foregroundStyle(isSelected ? Color.onAccent : Color.textPrimary)
        .background(isSelected ? Color.accent : Color.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .contentShape(Rectangle())
    }

    private var full: some View {
        HStack(spacing: Space.m) {
            Image(systemName: decision.icon)
                .foregroundStyle(isSelected ? Color.onAccent : Color.accent)
                .frame(width: Size.iconTile, height: Size.iconTile)
                .background(isSelected ? Color.accent : Color.surface,
                            in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(resolvedTitle).font(.bodyStrong).foregroundStyle(Color.textPrimary)
                if let detail { Text(detail).font(.footnoteText).foregroundStyle(Color.textTertiary) }
            }
            Spacer(minLength: Space.s)
            if isSelected { Image(systemName: "checkmark").foregroundStyle(Color.accent).accessibilityHidden(true) }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(minHeight: Size.row)
        .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
            .strokeBorder(isSelected ? Color.accent : .clear, lineWidth: Stroke.bold))
        .contentShape(Rectangle())
    }
}
