#if DEBUG
import SwiftUI

/// Every token and component on one page, in every state. Debug builds only:
/// long-press the logo on the Rooms screen, or launch with `-designSystem`.
/// Change a value in Theme and this page shows the effect at once.
struct DesignSystemGallery: View {
    @Environment(\.dismiss) private var dismiss
    @State private var background = Theme.background

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    section("Background") {
                        ChipPicker(options: [.init(value: PageBackground.brown, title: "Brown gradient"),
                                             .init(value: PageBackground.sage, title: "Sage gradient")],
                                   selection: $background, accessibilityLabel: "Background")
                    }
                    GallerySamples()
                }
                .pagePadding()
                .padding(.bottom, Size.floatingClearance)
            }
            .pageBackground()
            .environment(\.pageBackgroundStyle, background)
            .appNavigation("Design system", large: true)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .floatingAction("New room") {}
        }
    }
}

/// All the sample groups, in order.
private struct GallerySamples: View {
    var body: some View {
        section("Colours") { ColourSwatches() }
        section("Type") { TypeSamples() }
        section("Spacing and radii") { SpacingSamples() }
        section("Buttons") { ButtonSamples() }
        section("Chips and choices") { SelectionSamples() }
        section("Tags") { TagSamples() }
        section("Decision buttons") { DecisionSamples() }
        section("Cards, notes and rows") { NoteSamples() }
        section("Inputs and progress") { InputSamples() }
        section("Room cards") { RoomCardSamples() }
        section("People, badges and bars") { BadgeSamples() }
        section("Floor plan") { FloorPlanSample() }
        section("Inside a sheet (white)") {
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

private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: Space.m) {
        Text(title).textRole(.sectionTitle).accessibilityAddTraits(.isHeader)
        content()
    }
}

// MARK: - Samples (each is also a #Preview below)

private struct ColourSwatches: View {
    private let swatches: [(String, Color)] = [
        ("surface", .surface), ("surfaceMuted", .surfaceMuted), ("track", .track), ("outline", .outline),
        ("outlineStrong", .outlineStrong), ("divider", .divider), ("textPrimary", .textPrimary), ("textSecondary", .textSecondary),
        ("brand", .brand), ("iconNeutral", .iconNeutral), ("accent", .accent), ("onAccent", .onAccent),
        ("tintBrown", .tintBrown), ("tintSage", .tintSage), ("tintSlate", .tintSlate), ("tintBrick", .tintBrick),
        ("keep", .keep), ("send", .send), ("letGo", .letGo),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Size.catalogueTileMin), spacing: Space.s)], spacing: Space.s) {
                ForEach(swatches, id: \.0) { name, colour in
                    HStack(spacing: Space.s) {
                        Circle().fill(colour).frame(width: Size.tick, height: Size.tick)
                            .overlay(Circle().strokeBorder(Color.outline))
                        Text(name).textRole(.secondary)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            FlowLayout {
                ForEach(Tone.allCases, id: \.self) { tone in
                    Text(String(describing: tone).capitalized)
                        .font(.detailStrong).foregroundStyle(tone.text)
                        .padding(.horizontal, Space.l).frame(minHeight: Size.tag)
                        .background(tone.fill, in: Capsule())
                        .overlay(Capsule().strokeBorder(tone.line, lineWidth: Stroke.regular))
                }
            }
        }
    }
}

private struct TypeSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(TextRole.allCases.enumerated()), id: \.offset) { _, role in
                Text(String(describing: role)).textRole(role)
            }
            KVRow(label: "Room code", value: "K7M2Q", valueFont: .code, tracking: Tracking.code) { EmptyView() }
        }
    }
}

private struct SpacingSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach([("xs", Space.xs), ("s", Space.s), ("m", Space.m), ("l", Space.l), ("xl", Space.xl), ("xxl", Space.xxl),
                     ("xxxl", Space.xxxl)], id: \.0) { name, value in
                HStack {
                    Text(name).textRole(.secondary).frame(width: Size.floatingButton, alignment: .leading)
                    Capsule().fill(Color.accent).frame(width: value, height: Space.s)
                }
            }
            HStack(spacing: Space.s) {
                ForEach([Radius.thumb, Radius.tile, Radius.card, Radius.cardLarge, Radius.sheet], id: \.self) { r in
                    RoundedRectangle(cornerRadius: r).fill(Color.surface)
                        .frame(width: Size.roomTile * 0.7, height: Size.roomTile * 0.7)
                        .elevation(.card)
                }
            }
        }
    }
}

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
            TextField("Note", text: .constant("Please keep the case too"), axis: .vertical).textFieldStyle(.appArea)
            LengthStepper(label: "Width", value: $length, range: 150...800, units: .feet)
            ProgressBar(value: 0.6)
            ProgressSegments(count: 4, current: 1)
        }
    }
}

private struct RoomCardSamples: View {
    var body: some View {
        VStack(spacing: Space.l) {
            ForEach(Array(Theme.roomTints.enumerated()), id: \.offset) { i, tint in
                RoomCard(name: ["Alex’s old room", "Spare room", "Garage"][i], plannedUse: i == 0 ? "Study" : "",
                         status: ["4 waiting for Alex, 1 for you", "All decided", "Nothing listed yet"][i],
                         progress: [0.4, 1, nil][i], tint: tint)
            }
        }
    }
}

private struct BadgeSamples: View {
    @State private var tab = 0
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
            AppTabBar(items: [.init(value: 0, title: "Items", symbol: "list.bullet", badge: 3),
                              .init(value: 1, title: "Room plan", symbol: "cube")], selection: $tab)
                .padding(.horizontal, -Space.page)
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
            c.stroke(Path(room), with: .color(.textPrimary), lineWidth: Stroke.heavy)
            var window = Path()
            window.move(to: CGPoint(x: room.midX - room.width * 0.15, y: room.minY))
            window.addLine(to: CGPoint(x: room.midX + room.width * 0.15, y: room.minY))
            c.stroke(window, with: .color(.tintSlate), lineWidth: Stroke.heavy * 2.4)
            c.stroke(window, with: .color(.send), lineWidth: Stroke.hairline)
        }
        .aspectRatio(1.3, contentMode: .fit)
        .card(padding: 0, radius: Radius.cardLarge)
        .accessibilityLabel("Floor plan sample")
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
#Preview("Buttons") { PreviewStates { ButtonSamples() } }
#Preview("Selection") { PreviewStates { SelectionSamples() } }
#Preview("Tags") { PreviewStates { TagSamples() } }
#Preview("Decisions") { PreviewStates { DecisionSamples() } }
#Preview("Notes and rows") { PreviewStates { NoteSamples() } }
#Preview("Inputs") { PreviewStates { InputSamples() } }
#Preview("Room cards") { PreviewStates { RoomCardSamples() } }
#Preview("Badges and bars") { PreviewStates { BadgeSamples() } }
#Preview("Floor plan") { PreviewStates { FloorPlanSample() } }
#Preview("Colours") { PreviewStates { ColourSwatches() } }
#Preview("Type") { PreviewStates { TypeSamples() } }
#endif
