#if DEBUG
import SwiftUI
import UIKit

/// Debug builds only: room ⋯ menu → "Accessibility check" (or launch with `-a11yCheck`).
/// Evidence for the audit, computed live from the asset catalog:
/// * every text/icon colour pair in the design system, with swatches and its WCAG contrast ratio in
///   light and dark mode (and with Increase Contrast), marked ✓ AA or ✗;
/// * a photo pin with its 44 × 44 pt tap area outlined, and close pins nudged apart;
/// * the current Reduce Motion, text size, Increase Contrast and VoiceOver settings.
struct AccessibilityCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    private var results: [A11yPair.Result] { A11yPair.all.map { $0.evaluate() } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    settings
                    summary
                    SectionLabel("Contrast (WCAG 2.2 AA)")
                    Text("Text needs 4.5:1 (3:1 when 18 pt+, or 14 pt+ bold). Icons, outlines and control borders need 3:1. Each pair shows its worst background.")
                        .textRole(.hint)
                    ForEach(results) { row($0) }
                    SectionLabel("Tap targets")
                    tapTargets
                }
                .padding(Space.page)
            }
            .appSheet()
            .appNavigation("Accessibility check")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel("Settings right now")
            setting("Reduce Motion", reduceMotion ? "On: no slides, springs or camera inertia" : "Off", on: reduceMotion)
            setting("Text size", "\(typeSize)".replacingOccurrences(of: "DynamicTypeSize.", with: ""), on: typeSize.isAccessibilitySize)
            setting("Increase Contrast", contrast == .increased ? "On" : "Off", on: contrast == .increased)
            setting("Appearance", scheme == .dark ? "Dark" : "Light", on: scheme == .dark)
            setting("VoiceOver", UIAccessibility.isVoiceOverRunning ? "On" : "Off", on: UIAccessibility.isVoiceOverRunning)
        }
        .card(padding: Space.l, radius: Radius.tile)
    }

    private func setting(_ name: String, _ value: String, on: Bool) -> some View {
        HStack {
            Text(name).textRole(.bodyStrong)
            Spacer()
            Label(value, systemImage: on ? "checkmark.circle.fill" : "circle")
                .textRole(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: some View {
        let checks = results.flatMap(\.modes)
        let failed = checks.filter { !$0.passes }.count
        return Label(failed == 0 ? "All \(checks.count) checks pass AA" : "\(failed) of \(checks.count) checks fail",
                     systemImage: failed == 0 ? "checkmark.seal.fill" : "xmark.octagon.fill")
            .font(.bodyStrong)
            .foregroundStyle(failed == 0 ? Tone.sage.text : Tone.brick.text)
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(failed == 0 ? Tone.sage.fill : Tone.brick.fill, in: RoundedRectangle(cornerRadius: Radius.tile))
    }

    // MARK: Contrast rows

    private func row(_ r: A11yPair.Result) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(r.pair.name).textRole(.bodyStrong)
            Text("\(r.pair.foreground) on \(r.pair.backgrounds.joined(separator: ", ")) · needs \(r.pair.minimum.formatted()):1\(r.pair.lightOnly ? " · always drawn in light colours" : "")")
                .textRole(.hint)
            AdaptiveStack(spacing: Space.m) {
                ForEach(r.modes.filter { !$0.highContrast }) { m in modeCell(r.pair, m) }
            }
            let hc = r.modes.filter(\.highContrast)
            if !hc.isEmpty {
                Text("Increase Contrast: " + hc.map { "\($0.label) \($0.ratioText) \($0.passes ? "✓" : "✗")" }.joined(separator: " · "))
                    .textRole(.hint)
            }
        }
        .card(padding: Space.l, radius: Radius.tile)
        .accessibilityElement(children: .combine)
    }

    private func modeCell(_ pair: A11yPair, _ m: A11yPair.ModeResult) -> some View {
        HStack(spacing: Space.s) {
            // The swatch is drawn in that mode's colours, whatever mode the phone is in.
            ZStack {
                RoundedRectangle(cornerRadius: Radius.thumb).fill(Color(m.background, bundle: .main))
                if pair.isText {
                    Text("Aa").font(.bodyStrong).foregroundStyle(Color(pair.foreground, bundle: .main))
                } else {
                    Circle().strokeBorder(Color(pair.foreground, bundle: .main), lineWidth: Stroke.bold).padding(Space.s)
                }
            }
            .frame(width: Size.thumbnail, height: Size.tapTarget)
            .overlay(RoundedRectangle(cornerRadius: Radius.thumb).strokeBorder(Color.divider))
            .environment(\.colorScheme, m.dark ? .dark : .light)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(m.label).textRole(.hint)
                Text("\(m.ratioText):1").font(.bodyStrong).monospacedDigit().foregroundStyle(Color.textPrimary)
                Text(m.passes ? "✓ AA" : "✗ fails").font(.detailStrong)
                    .foregroundStyle(m.passes ? Color.accent : Color.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tap targets

    private var tapTargets: some View {
        let pins = [
            PhotoPin(id: UUID(), number: 1, label: "Desk", point: CGPoint(x: 0.30, y: 0.5)),
            PhotoPin(id: UUID(), number: 2, label: "Guitar", point: CGPoint(x: 0.36, y: 0.55), status: .keep),
            PhotoPin(id: UUID(), number: 3, label: "Lamp", point: CGPoint(x: 0.78, y: 0.45), status: .letGo),
        ]
        let frame = CGRect(x: 0, y: 0, width: 300, height: 150)
        let placed = PhotoWithPins.spreadApart(pins, in: frame, dragging: nil)
        return VStack(alignment: .leading, spacing: Space.s) {
            Text("Each pin is a 30 pt badge with an invisible 44 × 44 pt tap area (dashed). Pins 1 and 2 are saved 18 pt apart; on screen they're nudged so their tap areas don't overlap.")
                .textRole(.hint)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.tile).fill(Color(uiColor: UIColor(hex: 0xB58E66)))
                ForEach(pins) { pin in
                    let p = placed[pin.id] ?? .zero
                    // Where it's saved (small dot) …
                    Circle().fill(Color.photoBadge.opacity(0.7))
                        .frame(width: 6, height: 6)
                        .position(x: pin.point.x * frame.width, y: pin.point.y * frame.height)
                    // … and where it's drawn, with its tap area.
                    ZStack {
                        Rectangle()
                            .strokeBorder(Color.photoBadge, style: StrokeStyle(lineWidth: Stroke.regular, dash: Stroke.dashed))
                            .frame(width: Size.tapTarget, height: Size.tapTarget)
                        NumberBadge(number: pin.number, ring: pin.status == .undecided ? .accent : pin.status.color, placement: .onPhoto)
                    }
                    .position(p)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .accessibilityElement()
            .accessibilityLabel("Three sample pins with 44 by 44 point tap areas that don't overlap")
            Text("Buttons are 52 pt tall (44 pt compact), chips and tags 44 pt, icon buttons 44 × 44 pt, the back button 48 pt, tabs 52 pt, room-shape handles a 44 pt reach.")
                .textRole(.hint)
        }
        .card(padding: Space.l, radius: Radius.tile)
    }
}

// MARK: - The colour pairs (the same list as the audit table)

struct A11yPair: Identifiable {
    let name: String
    let foreground: String
    let backgrounds: [String]
    /// 4.5 for text, 3 for icons, outlines and control borders.
    let minimum: Double
    /// Photo badges are always drawn with the light palette.
    var lightOnly = false

    var id: String { name }
    var isText: Bool { minimum >= 4.5 }

    static let pageBackgrounds = ["surface", "surfaceMuted", "backgroundBrownTop", "backgroundBrownMiddle", "backgroundBrownBottom"]

    static let all: [A11yPair] = {
        var p: [A11yPair] = [
            .init(name: "Primary text", foreground: "textPrimary", backgrounds: pageBackgrounds + ["track"], minimum: 4.5),
            .init(name: "Secondary text and hints", foreground: "textSecondary", backgrounds: pageBackgrounds, minimum: 4.5),
            .init(name: "Primary button label", foreground: "accent", backgrounds: ["surface", "track", "surfaceMuted"], minimum: 4.5),
            .init(name: "Neutral button label and icons", foreground: "iconNeutral",
                  backgrounds: ["surface", "track", "surfaceMuted", "backgroundBrownTop", "backgroundBrownMiddle", "backgroundBrownBottom"], minimum: 4.5),
            .init(name: "Destructive label and error text", foreground: "letGo",
                  backgrounds: ["surface", "track", "surfaceMuted", "backgroundBrownTop", "backgroundBrownMiddle", "backgroundBrownBottom"], minimum: 4.5),
            .init(name: "Send decision text", foreground: "send", backgrounds: ["surface", "surfaceMuted"], minimum: 4.5),
        ]
        for t in ["Sage", "Slate", "Brick", "Brown"] {
            p.append(.init(name: "\(t) tag and selected text", foreground: "tone\(t)Text", backgrounds: ["tone\(t)Start", "tone\(t)End"], minimum: 4.5))
        }
        p += [
            .init(name: "Text on accent (selected badge, + button)", foreground: "onAccent", backgrounds: ["accent"], minimum: 4.5),
            .init(name: "Text on brand", foreground: "onBrand", backgrounds: ["brand"], minimum: 4.5),
            .init(name: "Pin number on photo badge", foreground: "onPhoto", backgrounds: ["photoBadge"], minimum: 4.5, lightOnly: true),
        ]
        for (t, icon) in [("Sage", "accent"), ("Slate", "send"), ("Brick", "letGo"), ("Brown", "iconNeutral")] {
            p.append(.init(name: "\(t) icon on tint circle", foreground: icon, backgrounds: ["tint\(t)"], minimum: 3))
        }
        for t in ["Sage", "Slate", "Brick", "Brown"] {
            p.append(.init(name: "\(t) selected outline", foreground: "tone\(t)Line", backgrounds: pageBackgrounds + ["tone\(t)Start", "tone\(t)End"], minimum: 3))
        }
        p += [
            .init(name: "Button, chip and toggle border", foreground: "outline", backgrounds: pageBackgrounds + ["track"], minimum: 3),
            .init(name: "Text field border", foreground: "outlineStrong", backgrounds: ["surface", "surfaceMuted"], minimum: 3),
            .init(name: "Progress bar fill on track", foreground: "accent", backgrounds: ["track", "trackOnMuted"], minimum: 3),
            .init(name: "Pin ring: keep", foreground: "accent", backgrounds: ["photoBadge"], minimum: 3, lightOnly: true),
            .init(name: "Pin ring: send", foreground: "send", backgrounds: ["photoBadge"], minimum: 3, lightOnly: true),
            .init(name: "Pin ring: let go", foreground: "letGo", backgrounds: ["photoBadge"], minimum: 3, lightOnly: true),
            .init(name: "Pin name label (white on dark scrim)", foreground: "photoBadge", backgrounds: ["onPhoto"], minimum: 4.5),
            .init(name: "Plan label on furniture", foreground: "textPrimary", backgrounds: ["tintBrown", "tintSage"], minimum: 4.5),
            .init(name: "Plan label, leaving (on floor)", foreground: "textSecondary", backgrounds: ["surface"], minimum: 4.5),
            .init(name: "Plan furniture outline", foreground: "iconNeutral", backgrounds: ["surface", "tintBrown"], minimum: 3),
            .init(name: "Plan new piece outline", foreground: "accent", backgrounds: ["surface", "tintSage"], minimum: 3),
            .init(name: "Plan walls", foreground: "textPrimary", backgrounds: ["surface", "surfaceMuted"], minimum: 3),
        ]
        return p
    }()

    struct ModeResult: Identifiable {
        let dark: Bool
        let highContrast: Bool
        let ratio: Double
        let minimum: Double
        let background: String
        var id: String { label }
        var label: String { (dark ? "Dark" : "Light") + (highContrast ? "+" : "") }
        var passes: Bool { ratio >= minimum - 0.005 }
        var ratioText: String { String(format: "%.2f", ratio) }
    }

    struct Result: Identifiable {
        let pair: A11yPair
        let modes: [ModeResult]
        var id: String { pair.id }
    }

    func evaluate() -> Result {
        var out: [ModeResult] = []
        for dark in [false, true] where !(lightOnly && dark) {
            for high in [false, true] {
                let traits = UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: dark ? .dark : .light),
                    UITraitCollection(accessibilityContrast: high ? .high : .normal),
                ])
                var worst: (Double, String) = (.infinity, "")
                for bg in backgrounds {
                    let r = Self.ratio(foreground, on: bg, traits: traits)
                    if r < worst.0 { worst = (r, bg) }
                }
                out.append(ModeResult(dark: dark, highContrast: high, ratio: worst.0, minimum: minimum, background: worst.1))
            }
        }
        return Result(pair: self, modes: out)
    }

    /// WCAG contrast ratio; a translucent foreground is composited over the background first.
    static func ratio(_ fg: String, on bg: String, traits: UITraitCollection) -> Double {
        let f = rgba(fg, traits), b = rgba(bg, traits)
        let mixed = (0..<3).map { f[$0] * f[3] + b[$0] * (1 - f[3]) }
        let l1 = luminance(mixed), l2 = luminance(Array(b[0..<3]))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private static func rgba(_ name: String, _ traits: UITraitCollection) -> [Double] {
        let c = (UIColor(named: name) ?? .magenta).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { Double(min(max($0, 0), 1)) }
    }

    private static func luminance(_ c: [Double]) -> Double {
        let l = c.map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
    }
}
#endif
