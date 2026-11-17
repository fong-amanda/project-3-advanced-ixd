#if DEBUG
import SwiftUI
import UIKit

/// Every token and component in ios/DESIGN_SYSTEM.md on one page, in the file's order and in every
/// state. Debug builds only: room ⋯ menu → "Design system", long-press the logo on Rooms, or launch
/// with `-designSystem` (add `-designSystemSection colors` to jump to a section).
/// Change a value in Theme or the asset catalog and this page shows it at once.
struct DesignSystemGallery: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme
    @State private var background = Theme.background
    @State private var appearance: Appearance = .system
    @State private var largerText = false

    enum Appearance: Hashable { case system, light, dark }

    /// The sections, in the same order and with the same names as DESIGN_SYSTEM.md.
    static let sections: [(id: String, title: String)] = [
        ("colors", "Color tokens"), ("decisions", "Decisions"), ("backgrounds", "Backgrounds"),
        ("tones", "Selected state and tags"), ("type", "Typography"), ("spacing", "Shape, spacing and depth"),
        ("buttons", "Buttons"), ("chips", "Chips and choices"), ("tags", "Tags"), ("decisionButtons", "Decision buttons"),
        ("cards", "Cards, notes and rows"), ("inputs", "Inputs and progress"), ("roomCards", "Room cards"),
        ("bars", "People, badges and bars"), ("pins", "Photo pins"), ("floorPlan", "Floor plan"),
        ("goals", "Room goals"), ("menus", "Archive and Delete"), ("consent", "Consent sheet (Before you scan)"),
        ("detection", "Suggestions from detection"), ("sheet", "Inside a sheet (white)"),
    ]

    private var scheme: ColorScheme {
        switch appearance {
        case .system: systemScheme
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        previewControls
                        GallerySamples(background: $background)
                            .dynamicTypeSize(largerText ? .accessibility2 : .large)
                    }
                    .pagePadding()
                    .padding(.bottom, Size.floatingClearance)
                }
                .onAppear {
                    if let id = Self.requestedSection {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
            .pageBackground()
            .environment(\.pageBackgroundStyle, background)
            .environment(\.colorScheme, scheme)
            .appNavigation("Design system", large: true)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear {
            if let s = DemoData.colorScheme { appearance = s == .dark ? .dark : .light }
        }
    }

    /// Preview the page in light mode, dark mode and with larger text.
    private var previewControls: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ChipPicker(options: [.init(value: Appearance.system, title: "System"),
                                 .init(value: Appearance.light, title: "Light"),
                                 .init(value: Appearance.dark, title: "Dark")],
                       selection: $appearance, accessibilityLabel: "Preview appearance")
            ToggleRow(title: "Larger text", subtitle: "Shows the page at an accessibility text size", isOn: $largerText)
        }
    }

    /// `-designSystemSection <id>`: scroll to a section on open (for screenshots).
    static var requestedSection: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-designSystemSection"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
}

/// All the sample groups, in the file's order.
private struct GallerySamples: View {
    @Binding var background: PageBackground

    var body: some View {
        section("colors") { ColourTokens() }
        section("decisions") { DecisionTable() }
        section("backgrounds") { BackgroundSamples(background: $background) }
        section("tones") { ToneSamples() }
        section("type") { TypeSamples() }
        section("spacing") { SpacingSamples() }
        section("buttons") { ButtonSamples() }
        section("chips") { SelectionSamples() }
        section("tags") { TagSamples() }
        section("decisionButtons") { DecisionSamples() }
        section("cards") { NoteSamples() }
        section("inputs") { InputSamples() }
        section("roomCards") { RoomCardSamples() }
        section("bars") { BadgeSamples() }
        section("pins") { PinSamples() }
        section("floorPlan") { FloorPlanSample() }
        section("goals") { GoalSamples() }
        section("menus") { MenuSamples() }
        section("consent") { ConsentSamples() }
        section("detection") { DetectionSamples() }
        section("sheet") {
            VStack(alignment: .leading, spacing: Space.m) {
                NoteSamples()
                InputSamples()
            }
            .padding(Space.l)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .environment(\.onWhiteSurface, true)
        }
    }
}

private func section<Content: View>(_ id: String, @ViewBuilder content: () -> Content) -> some View {
    let title = DesignSystemGallery.sections.first { $0.id == id }?.title ?? id
    return VStack(alignment: .leading, spacing: Space.m) {
        Text(title).textRole(.sectionTitle).accessibilityAddTraits(.isHeader)
        content()
    }
    .id(id)
}

// MARK: - Token data (read live from the asset catalog)

/// One colour token: its asset name, what it's for, and the background its contrast is checked on.
private struct Token: Identifiable {
    let name: String
    let use: String
    var on: String = "surface"
    /// 4.5 for text, 3 for icons, outlines and controls, 0 when it isn't used on anything (a background).
    var needs: Double = 4.5
    var id: String { name }
}

private enum Tokens {
    static let groups: [(String, [Token])] = [
        ("Neutrals", [
            Token(name: "surface", use: "Cards, buttons, sheets", needs: 0),
            Token(name: "surfaceMuted", use: "Card fill on white (Mist)", needs: 0),
            Token(name: "track", use: "Progress track, pressed rows", needs: 0),
            Token(name: "trackOnMuted", use: "Progress track on Mist", needs: 0),
            Token(name: "outline", use: "Button, chip, toggle borders", on: "backgroundBrownTop", needs: 3),
            Token(name: "outlineStrong", use: "Text field borders, tick rings", needs: 3),
            Token(name: "divider", use: "Decorative lines only", needs: 0),
            Token(name: "textPrimary", use: "Main text (Ink)", on: "backgroundBrownTop"),
            Token(name: "textSecondary", use: "Secondary text (Graphite)", on: "backgroundBrownTop"),
        ]),
        ("Brand", [
            Token(name: "brand", use: "Brand areas (white text only)", needs: 0),
            Token(name: "onBrand", use: "Text on brand", on: "brand"),
            Token(name: "iconNeutral", use: "Icons, neutral button labels", on: "backgroundBrownTop"),
            Token(name: "accent", use: "Main accent, Keep, progress (Sage)"),
            Token(name: "onAccent", use: "Text and icons on accent", on: "accent"),
            Token(name: "tintBrown", use: "Avatar and icon circles", needs: 0),
            Token(name: "tintSage", use: "Icon circles, highlights", needs: 0),
            Token(name: "tintSlate", use: "Icon circles, room tiles", needs: 0),
            Token(name: "tintBrick", use: "Icon circles for letting go", needs: 0),
        ]),
        ("Decisions", [
            Token(name: "accent", use: "keep: Keep"),
            Token(name: "send", use: "send: Send to owner (Slate)"),
            Token(name: "letGo", use: "letGo: Donate or sell, Throw out, destructive (Brick)"),
        ]),
        ("Photos and 3D", [
            Token(name: "photoBadge", use: "Pin badges on photos (always white)", needs: 0),
            Token(name: "onPhoto", use: "Pin numbers; dark scrim behind pin labels", on: "photoBadge"),
            Token(name: "roomFloor", use: "3D floor", needs: 0),
            Token(name: "roomWall", use: "3D walls", needs: 0),
            Token(name: "roomWindow", use: "3D windows", needs: 0),
            Token(name: "roomDoor", use: "3D doors", needs: 0),
            Token(name: "shadow", use: "Shadow colour (Ink)", needs: 0),
        ]),
    ]

    static func traits(_ scheme: ColorScheme) -> UITraitCollection {
        UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
    }

    static func hex(_ name: String, _ scheme: ColorScheme) -> String {
        let c = (UIColor(named: name) ?? .magenta).resolvedColor(with: traits(scheme))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

private struct ColourTokens: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Values for \(scheme == .dark ? "dark" : "light") mode, read from the asset catalog. The ratio is against the background in brackets.")
                .textRole(.hint)
            ForEach(Tokens.groups, id: \.0) { group, tokens in
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(group).textRole(.bodyStrong)
                    VStack(spacing: 0) {
                        ForEach(tokens) { t in
                            row(t)
                            if t.id != tokens.last?.id { Hairline(inset: Space.l + Size.iconCircle + Space.m) }
                        }
                    }
                    .listGroup()
                }
            }
        }
    }

    private func row(_ t: Token) -> some View {
        let ratio = A11yPair.ratio(t.name, on: t.on, traits: Tokens.traits(scheme))
        return HStack(spacing: Space.m) {
            RoundedRectangle(cornerRadius: Radius.thumb).fill(Color(t.name, bundle: .main))
                .frame(width: Size.iconCircle, height: Size.iconCircle)
                .overlay(RoundedRectangle(cornerRadius: Radius.thumb).strokeBorder(Color.divider))
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(t.name).textRole(.bodyStrong)
                Text(t.use).textRole(.hint)
            }
            Spacer(minLength: Space.s)
            VStack(alignment: .trailing, spacing: Space.xs) {
                Text(Tokens.hex(t.name, scheme)).font(.detailStrong).monospaced().foregroundStyle(Color.textPrimary)
                if t.needs > 0 {
                    Text("\(String(format: "%.2f", ratio)):1 \(ratio >= t.needs - 0.005 ? "✓" : "✗") (\(t.on))")
                        .font(.badge).foregroundStyle(ratio >= t.needs - 0.005 ? Color.textSecondary : Color.danger)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
    }
}

/// Every decision: colour + symbol + words, with each label it uses.
private struct DecisionTable: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(([ItemStatus.undecided] + ItemStatus.decisions + [.keepMove]).enumerated()), id: \.offset) { i, d in
                HStack(spacing: Space.m) {
                    Image(systemName: d.icon)
                        .font(.bodyStrong).foregroundStyle(d.tone.icon)
                        .dynamicTypeSize(...Size.iconTypeLimit)
                        .frame(width: Size.iconCircle, height: Size.iconCircle)
                        .background(d.tone.tint, in: Circle())
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(d.shortLabel + (d == .keepMove ? " (older items only)" : "")).textRole(.bodyStrong)
                        Text("\(d.label) · “\(d.statusLabel)” · \(d.icon) · \(String(describing: d.tone).capitalized)")
                            .textRole(.hint)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                .accessibilityElement(children: .combine)
                if i < ItemStatus.decisions.count + 1 { Hairline(inset: Space.l + Size.iconCircle + Space.m) }
            }
        }
        .listGroup()
    }
}

private struct BackgroundSamples: View {
    @Binding var background: PageBackground
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                ForEach([(PageBackground.brown, "Brown (default)", "backgroundBrown"), (.sage, "Sage", "backgroundSage")], id: \.1) { bg, name, key in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        RoundedRectangle(cornerRadius: Radius.tile).fill(bg.gradient)
                            .frame(height: Size.roomTile * 1.4)
                            .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Color.divider))
                        Text(name).textRole(.bodyStrong)
                        Text(["Top", "Middle", "Bottom"].map { Tokens.hex(key + $0, scheme) }.joined(separator: " → "))
                            .font(.badge).monospaced().foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Top to bottom, middle stop at 45%. The page uses one of them everywhere (Theme.background).").textRole(.hint)
            ChipPicker(options: [.init(value: PageBackground.brown, title: "Show brown"),
                                 .init(value: PageBackground.sage, title: "Show sage")],
                       selection: $background, accessibilityLabel: "Page background")
        }
    }
}

private struct ToneSamples: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: Space.s) {
            ForEach(Tone.allCases, id: \.self) { tone in
                let n = String(describing: tone).capitalized
                HStack(spacing: Space.m) {
                    Text(n).font(.detailStrong).foregroundStyle(tone.text)
                        .padding(.horizontal, Space.l).frame(minHeight: Size.tag)
                        .background(tone.fill, in: Capsule())
                        .overlay(Capsule().strokeBorder(tone.line, lineWidth: Stroke.regular))
                    Text("text \(Tokens.hex("tone\(n)Text", scheme)) · \(Tokens.hex("tone\(n)Start", scheme)) → \(Tokens.hex("tone\(n)End", scheme)) · outline \(Tokens.hex("tone\(n)Line", scheme))")
                        .font(.badge).monospaced().foregroundStyle(Color.textSecondary)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Gradient at 135°. The outline only appears on selected buttons, chips and tabs; tags have none.").textRole(.hint)
        }
    }
}

private struct TypeSamples: View {
    private let styles: [(TextRole, String)] = [
        (.largeTitle, "Large title · 34 pt semibold"), (.screenTitle, "Title · 22 pt semibold"),
        (.sectionTitle, "Section title · 20 pt semibold"), (.cardTitle, "Headline · 20 pt medium"),
        (.body, "Body · 17 pt regular"), (.bodyStrong, "Body strong · 17 pt medium"),
        (.secondary, "Secondary · 16 pt regular, Graphite"), (.error, "Error · 16 pt medium, Brick"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(styles.enumerated()), id: \.offset) { _, s in Text(s.1).textRole(s.0) }
            Text("Badge · 13 pt medium (numbers on pins and plans)").font(.badge).foregroundStyle(Color.textPrimary)
            Text("Button · 17 pt medium").font(.button).foregroundStyle(Color.textPrimary)
            KVRow(label: "Room code", value: "K7M2Q", valueFont: .code, tracking: Tracking.code) { EmptyView() }
            Text("All are Dynamic Type text styles, so they grow with the text size setting.").textRole(.hint)
        }
    }
}

private struct SpacingSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach([("xs", Space.xs), ("s", Space.s), ("m", Space.m), ("l", Space.l), ("xl", Space.xl), ("xxl · page", Space.xxl),
                     ("xxxl", Space.xxxl)], id: \.0) { name, value in
                HStack {
                    Text("\(name) \(Int(value))").textRole(.secondary).frame(width: Size.floatingButton * 2, alignment: .leading)
                    Capsule().fill(Color.accent).frame(width: value, height: Space.s)
                }
            }
            HStack(alignment: .top, spacing: Space.s) {
                ForEach([("thumb", Radius.thumb), ("tile", Radius.tile), ("card", Radius.card), ("large", Radius.cardLarge), ("sheet", Radius.sheet)], id: \.0) { name, r in
                    VStack(spacing: Space.xs) {
                        RoundedRectangle(cornerRadius: r).fill(Color.surface)
                            .frame(width: Size.roomTile * 0.62, height: Size.roomTile * 0.62)
                            .elevation(.card)
                        Text("\(name) \(Int(r))").font(.badge).foregroundStyle(Color.textSecondary)
                    }
                }
            }
            HStack(spacing: Space.l) {
                ForEach([(Elevation.card, "Card shadow · 6% + 7%"), (.floating, "Floating · 6% + 14%")], id: \.1) { e, name in
                    Text(name).textRole(.secondary)
                        .frame(maxWidth: .infinity, minHeight: Size.roomTile)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card))
                        .elevation(e)
                }
            }
            Text("Tap targets 44 × 44 pt or more; main buttons 52 pt; rows 60 pt; tags 32 pt.").textRole(.hint)
        }
    }
}

// MARK: - Components (each is also a #Preview below)

struct ButtonSamples: View {
    var body: some View {
        VStack(spacing: Space.s) {
            ForEach(AppButtonStyle.Role.allCases, id: \.self) { role in
                Button("\(String(describing: role).capitalized)") {}.buttonStyle(.app(role))
                HStack(spacing: Space.s) {
                    Button("Pressed") {}.buttonStyle(AppButtonStyle(role: role, size: .compact, previewPressed: true))
                    Button("Selected") {}.buttonStyle(.app(role, size: .compact, selected: true))
                    Button("Disabled") {}.buttonStyle(.app(role, size: .compact)).disabled(true)
                }
            }
            HStack(spacing: Space.s) {
                BackButton {}
                IconButton(symbol: "arrow.left", label: "Move left", filled: true) {}
                IconButton(symbol: "trash", label: "Remove", role: .destructive, filled: true) {}
                IconButton(symbol: "plus.magnifyingglass", label: "Zoom in") {}
            }
            FloatingActionButton(title: "New room") {}
        }
    }
}

struct SelectionSamples: View {
    @State private var pick = 0
    @State private var on = true
    @State private var off = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ChipPicker(options: [.init(value: 0, title: "For you to decide", count: 3),
                                 .init(value: 1, title: "Waiting for Alex", count: 4),
                                 .init(value: 2, title: "Decided")], selection: $pick)
            HStack(spacing: Space.s) {
                AppChip(title: "Study", isSelected: true) {}
                AppChip(title: "Guest room", isSelected: false) {}
                Button("Pressed") {}.buttonStyle(AppChipStyle(isSelected: false, previewPressed: true))
            }
            AppChip(title: "Disabled", isSelected: false) {}.disabled(true)
            PickRow(title: "Yes, there are items", isSelected: true) {}
            PickRow(title: "No, the room is empty", subtitle: "You can add things later", isSelected: false) {}
            ToggleRow(title: "I measured the room", subtitle: "Turns on fit checks", isOn: $on)
            ToggleRow(title: "Switch off", isOn: $off)
            HStack { TickBadge(isOn: true); TickBadge(isOn: false) }
        }
    }
}

struct TagSamples: View {
    var body: some View {
        FlowLayout(spacing: Space.s) {
            AppTag(kind: .owner(.host), text: "Mine")
            AppTag(kind: .owner(.guest), text: "Sam’s")
            AppTag(kind: .neutral, text: "Shared")
            AppTag(kind: .suggestion, text: "Alex: keep")
            AppTag(kind: .suggestion, text: DetectionCopy.suggestedTag, symbol: "questionmark.circle")
            AppTag(kind: .tone(.sage), text: "Confirmed", symbol: "checkmark")
            ForEach(ItemStatus.decisions, id: \.self) { AppTag(kind: .decision($0), text: $0.statusLabel) }
            AppTag(kind: .fit(.ok), text: Fit.ok.label)
            AppTag(kind: .fit(.tight), text: Fit.tight.label)
            AppTag(kind: .fit(.no), text: Fit.no.label)
        }
    }
}

struct DecisionSamples: View {
    var body: some View {
        VStack(spacing: Space.s) {
            ForEach(ItemStatus.decisions, id: \.self) { d in
                DecisionButton(decision: d, detail: d.detail, isSelected: d == .keep, layout: .full) {}
            }
            FlowLayout(spacing: Space.s) {
                ForEach(ItemStatus.decisions, id: \.self) { d in
                    DecisionButton(decision: d, isSelected: d == .letGo, layout: .compact) {}
                }
                DecisionButton(decision: .toss, layout: .compact, suggesting: true) {}.disabled(true)
            }
        }
    }
}

private struct NoteSamples: View {
    var body: some View {
        VStack(spacing: Space.s) {
            NoteBar(text: "Alex suggests: keep") { Button("Use it") {}.buttonStyle(.app(.primary, size: .compact)) }
            NoteBar(text: "1 placement needs a look", symbol: "exclamationmark.triangle", tone: .warning)
            KVRow(label: "Room code", value: "K7M2Q", valueFont: .codeSmall, tracking: Tracking.code) {
                Button("Copy") {}.buttonStyle(.app(.primary, size: .compact))
            }
            ChoiceTile(title: "Take a photo", detail: "Opens your camera", symbol: "camera")
            Text("A card").textRole(.body).card()
        }
    }
}

private struct InputSamples: View {
    @State private var length = 340.0
    var body: some View {
        VStack(spacing: Space.s) {
            TextField("Room name", text: .constant("Alex’s old room")).textFieldStyle(.app)
            TextField("Note", text: .constant(""), prompt: Text("Anything the other person should know").foregroundStyle(Color.textSecondary), axis: .vertical)
                .textFieldStyle(.appArea)
            LengthStepper(label: "Width", value: $length, range: 150...800, units: .feet)
            ProgressBar(value: 0.6)
            ProgressSegments(count: 5, current: 1)
        }
    }
}

private struct RoomCardSamples: View {
    var body: some View {
        VStack(spacing: Space.l) {
            RoomCard(name: "Alex’s old room", plannedUse: "Study", status: "4 waiting for Alex",
                     goals: [.init(title: RoomGoal.sort.tag, symbol: RoomGoal.sort.symbol, tone: RoomGoal.sort.tone, status: "3 of 7 decided"),
                             .init(title: RoomGoal.plan.tag, symbol: RoomGoal.plan.symbol, tone: RoomGoal.plan.tone, status: "No layouts yet")],
                     progress: 3 / 7, tint: .sage, reservesMenuCorner: true)
                .overlay(alignment: .topTrailing) { cornerMenu }
            RoomCard(name: "Spare room", plannedUse: "", status: "",
                     goals: [.init(title: RoomGoal.plan.tag, symbol: RoomGoal.plan.symbol, tone: RoomGoal.plan.tone, status: "2 layouts")],
                     tint: .brown, reservesMenuCorner: true)
                .overlay(alignment: .topTrailing) { cornerMenu }
            Text("Each goal is its own row: tag, then status. ⋯ opens Archive and Delete; so does touch and hold.").textRole(.hint)
        }
    }

    private var cornerMenu: some View {
        Image(systemName: "ellipsis").font(.bodyStrong).foregroundStyle(Color.textPrimary)
            .frame(width: Size.tapTarget - Space.l, height: Size.tapTarget - Space.l)
            .background(.regularMaterial, in: Circle())
            .frame(width: Size.tapTarget, height: Size.tapTarget)
            .padding(.top, Space.xl + Space.xs - Space.s).padding(.trailing, Space.xl + Space.xs - Space.s)
            .accessibilityLabel("Options")
    }
}

private struct BadgeSamples: View {
    @State private var tab = 0
    @State private var two = 0
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.m) {
                NumberBadge(number: 3)
                NumberBadge(number: 4, isSelected: true)
                NumberBadge(number: 5, ring: .letGo, placement: .onPhoto)
                NumberBadge(number: 6, size: Size.badgeSmall)
                Avatar(name: "Linda", role: .host)
                Avatar(name: "Alex", role: .guest, online: true)
                Avatar(name: "Alex", role: .guest, online: false)
                BrandMark().frame(width: Size.brandMark, height: Size.brandMark)
            }
            Text("Room tabs: Room and People always, Sort and Redesign per goal.").textRole(.hint)
            AppTabBar(items: [.init(value: 0, title: "Room", symbol: "house"),
                              .init(value: 1, title: "Sort", symbol: "checklist", badge: 3),
                              .init(value: 2, title: "Redesign", symbol: "cube"),
                              .init(value: 3, title: "People", symbol: "person.2")], selection: $tab)
                .padding(.horizontal, -Space.page)
            AppTabBar(items: [.init(value: 0, title: "Room", symbol: "house"),
                              .init(value: 1, title: "People", symbol: "person.2")], selection: $two)
                .padding(.horizontal, -Space.page)
            ActivityBannerSample(text: "Room archived", action: "Undo")
        }
    }
}

/// The undo banner's look, without its timer.
private struct ActivityBannerSample: View {
    let text: String
    let action: String
    var body: some View {
        HStack(spacing: Space.m) {
            IconCircle(symbol: "arrow.uturn.backward", tone: .sage)
            Text(text).font(.bodyStrong).foregroundStyle(Color.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
            Button(action) {}.buttonStyle(.app(.neutral, size: .compact)).fixedSize()
        }
        .padding(Space.m)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .elevation(.floating)
    }
}

/// Numbered pins on a photo: the decision's symbol on a small badge, "Name · Status" when selected,
/// and a 44-point tap area (close pins are spread apart).
private struct PinSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            PhotoWithPins(image: DemoData.samplePhoto(), pins: [
                PhotoPin(id: UUID(), number: 1, label: "Bed", point: CGPoint(x: 0.24, y: 0.68), statusText: "undecided", isSelected: true),
                PhotoPin(id: UUID(), number: 2, label: "Desk", point: CGPoint(x: 0.58, y: 0.56), status: .keep, statusText: "staying"),
                PhotoPin(id: UUID(), number: 3, label: "Guitar", point: CGPoint(x: 0.62, y: 0.58), status: .sendToOwner, statusText: "going to Alex"),
                PhotoPin(id: UUID(), number: 4, label: "Boxes", point: CGPoint(x: 0.82, y: 0.82), status: .letGo, statusText: "letting go"),
            ])
            .clipShape(RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
            Text("Pins 2 and 3 are saved 6% apart and drawn 44 pt apart. VoiceOver reads “1, Bed, undecided”.").textRole(.hint)
        }
    }
}

/// The floor plan's look: Ink walls, existing furniture in brown, new pieces dashed sage, a window.
private struct FloorPlanSample: View {
    var body: some View {
        Canvas { c, size in
            let room = CGRect(x: Space.l, y: Space.l, width: size.width - Space.l * 2, height: size.height - Space.l * 2)
            c.fill(Path(room), with: .color(.surface))
            let old = CGRect(x: room.minX + Space.m, y: room.minY + Space.m, width: room.width * 0.35, height: room.height * 0.4)
            c.fill(Path(roundedRect: old, cornerRadius: Radius.drawing), with: .color(.tintBrown))
            c.stroke(Path(roundedRect: old, cornerRadius: Radius.drawing), with: .color(.iconNeutral), lineWidth: Stroke.regular)
            let new = CGRect(x: room.midX, y: room.midY, width: room.width * 0.4, height: room.height * 0.3)
            c.fill(Path(roundedRect: new, cornerRadius: Radius.drawing), with: .color(.tintSage))
            c.stroke(Path(roundedRect: new, cornerRadius: Radius.drawing), with: .color(.accent),
                     style: StrokeStyle(lineWidth: Stroke.bold, dash: Stroke.dashed))
            let leaving = CGRect(x: room.minX + Space.m, y: room.maxY - room.height * 0.3, width: room.width * 0.3, height: room.height * 0.22)
            c.stroke(Path(roundedRect: leaving, cornerRadius: Radius.drawing), with: .color(.send),
                     style: StrokeStyle(lineWidth: Stroke.regular, dash: Stroke.dashed))
            c.draw(Text(Image(systemName: "shippingbox")) + Text(" Boxes"), at: CGPoint(x: leaving.midX, y: leaving.midY))
            c.stroke(Path(room), with: .color(.textPrimary), lineWidth: Stroke.heavy)
            var window = Path()
            window.move(to: CGPoint(x: room.midX - room.width * 0.15, y: room.minY))
            window.addLine(to: CGPoint(x: room.midX + room.width * 0.15, y: room.minY))
            c.stroke(window, with: .color(.tintSlate), lineWidth: Stroke.heavy * 2.4)
            c.stroke(window, with: .color(.send), lineWidth: Stroke.hairline)
        }
        .font(.badge)
        .foregroundStyle(Color.textSecondary)
        .aspectRatio(1.3, contentMode: .fit)
        .card(padding: 0, radius: Radius.cardLarge)
        .accessibilityLabel("Floor plan sample: existing furniture, a new piece, and boxes leaving the room")
    }
}

private struct GoalSamples: View {
    @State private var sort = true
    @State private var plan = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("What do you want to do with this room?").textRole(.bodyStrong)
            GoalPicker(sort: $sort, plan: $plan)
            Text("You can change this anytime. Nothing has to leave the room.").textRole(.hint)
        }
    }
}

/// The Archive / Delete menu (a system context menu and ⋯ menu), and the delete confirmation.
private struct MenuSamples: View {
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(spacing: 0) {
                menuRow("Archive", "archivebox", Color.textPrimary)
                Hairline(inset: Space.l)
                menuRow("Delete", "trash", Color.danger)
            }
            .listGroup()
            Text("Short labels only. Guests see “Leave Room” instead of Delete. Archive shows “Room archived. Undo”.").textRole(.hint)
            Button("Show the delete confirmation") { confirm = true }.buttonStyle(.app(.neutral, size: .compact))
                .confirmationDialog("Delete this room?", isPresented: $confirm, titleVisibility: .visible) {
                    Button("Delete Room", role: .destructive) {}
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This permanently removes the room, its scan and photo, every item and decision, all designs, and the room code. This can’t be undone.")
                }
        }
    }

    private func menuRow(_ title: String, _ symbol: String, _ color: Color) -> some View {
        HStack {
            Text(title).font(.bodyText).foregroundStyle(color)
            Spacer()
            Image(systemName: symbol).foregroundStyle(color)
        }
        .padding(.horizontal, Space.l).frame(minHeight: Size.tapTarget)
    }
}

/// "Before you add a photo" (the consent sheet) and "Who can see this?".
private struct ConsentSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            CaptureConsentSheet(onContinue: {}, onNotNow: {})
                .frame(height: 470)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
                .elevation(.floating)
            WhoCanSeeThisLink()
        }
    }
}

/// "How this works" and the suggestion rows from photo detection.
private struct DetectionSamples: View {
    @State private var how = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.xs) {
                Text(DetectionCopy.photoStepLead).textRole(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Button { how = true } label: {
                    Image(systemName: "info.circle").font(.button).foregroundStyle(Color.accent)
                        .frame(width: Size.tapTarget, height: Size.tapTarget)
                }
                .accessibilityLabel("How this works")
            }
            .alert(DetectionCopy.howTitle, isPresented: $how) { Button("Got it", role: .cancel) {} } message: { Text(DetectionCopy.howMessage) }
            NoteBar(text: DetectionReviewSheet.privacyNote, symbol: "lock.iphone")
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    NumberBadge(number: 1, size: Size.tick)
                    Text("Chair").textRole(.bodyStrong)
                }
                AppTag(kind: .suggestion, text: DetectionCopy.suggestedTag, symbol: "questionmark.circle")
                HStack(spacing: Space.s) {
                    Button {} label: { Label("Confirm", systemImage: "checkmark") }.buttonStyle(.app(.primary, size: .compact))
                    Button {} label: { Label("Remove", systemImage: "xmark") }.buttonStyle(.app(.neutral, size: .compact))
                }
            }
            .card(padding: Space.l, radius: Radius.tile)
        }
    }
}

// MARK: - Previews: every group in light, dark and large text

private struct PreviewStates<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                content
                content.padding(Space.m).pageBackground().environment(\.colorScheme, .dark)
                content.dynamicTypeSize(.accessibility3)
            }
            .pagePadding()
        }
        .pageBackground()
    }
}

#Preview("Gallery") { DesignSystemGallery() }
#Preview("Gallery · dark") { DesignSystemGallery().preferredColorScheme(.dark) }
#Preview("Gallery · large text") { DesignSystemGallery().dynamicTypeSize(.accessibility3) }
#Preview("Colour tokens") { PreviewStates { ColourTokens() } }
#Preview("Decisions") { PreviewStates { DecisionTable() } }
#Preview("Backgrounds") { PreviewStates { BackgroundSamples(background: .constant(.brown)) } }
#Preview("Tones") { PreviewStates { ToneSamples() } }
#Preview("Type") { PreviewStates { TypeSamples() } }
#Preview("Spacing and radii") { PreviewStates { SpacingSamples() } }
#Preview("Buttons") { PreviewStates { ButtonSamples() } }
#Preview("Selection") { PreviewStates { SelectionSamples() } }
#Preview("Tags") { PreviewStates { TagSamples() } }
#Preview("Decision buttons") { PreviewStates { DecisionSamples() } }
#Preview("Notes and rows") { PreviewStates { NoteSamples() } }
#Preview("Inputs") { PreviewStates { InputSamples() } }
#Preview("Room cards") { PreviewStates { RoomCardSamples() } }
#Preview("Badges and bars") { PreviewStates { BadgeSamples() } }
#Preview("Photo pins") { PreviewStates { PinSamples() } }
#Preview("Floor plan") { PreviewStates { FloorPlanSample() } }
#Preview("Room goals") { PreviewStates { GoalSamples() } }
#Preview("Archive and Delete") { PreviewStates { MenuSamples() } }
#Preview("Consent sheet") { PreviewStates { ConsentSamples() } }
#Preview("Detection") { PreviewStates { DetectionSamples() } }
#endif
