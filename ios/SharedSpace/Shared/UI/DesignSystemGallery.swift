#if DEBUG
import SwiftUI

/// Every token and component on one page, in every state. Debug builds only:
/// long-press the logo on the Rooms screen, or launch with `-designSystem`.
/// Change a value in Theme and this page shows the effect at once.
struct DesignSystemGallery: View {
    @Environment(\.dismiss) private var dismiss
    @State private var segment = 0
    @State private var tab = 0
    @State private var length = 340.0
    @State private var shape = RoomShape.preset(.lShape, width: 340, length: 380)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    section("Shape editor") { ShapeEditor(shape: $shape, units: .feet) }
                    section("Colours") { ColourSwatches() }
                    section("Type") { TypeSamples() }
                    section("Spacing and radii") { SpacingSamples() }
                    section("Buttons") { ButtonSamples() }
                    section("Links and icon buttons") { LinkSamples() }
                    section("Chips, pick rows, ticks") { SelectionSamples() }
                    section("Segments and tabs") {
                        SegmentedControl(segments: [.init(value: 0, title: "For you to decide", count: 3),
                                                    .init(value: 1, title: "Waiting for Alex", count: 4),
                                                    .init(value: 2, title: "Decided")], selection: $segment)
                        ScrollingSegments(options: [.init(value: 0, title: "Current room"),
                                                    .init(value: 1, title: "Proposed layout"),
                                                    .init(value: 2, title: "Shared 1", badge: "hand.thumbsup.fill", badgeLabel: "Looks good")],
                                          selection: tab) { tab = $0 }
                        UnderlineTabs(tabs: [(0, "Everything"), (1, "Beds"), (2, "Seating"), (3, "Storage")], selection: $tab)
                    }
                    section("Tags") { TagSamples() }
                    section("Decision buttons") { DecisionSamples() }
                    section("Notes and rows") { NoteSamples() }
                    section("Inputs") {
                        TextField("Room name", text: .constant("Alex’s old room")).textFieldStyle(.app)
                        TextField("Note", text: .constant("Please keep the case too"), axis: .vertical).textFieldStyle(.appArea)
                        LengthStepper(label: "Width", value: $length, range: 150...800, units: .feet)
                        ProgressSegments(count: 4, current: 1)
                    }
                    section("Room cards") { RoomCardSamples() }
                    section("Badges and people") { BadgeSamples() }
                }
                .pagePadding()
            }
            .background(Color.pageBackground)
            .navigationTitle("Design system")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title).textRole(.sectionTitle).accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

// MARK: - Samples (each is also a #Preview below)

private struct ColourSwatches: View {
    private let swatches: [(String, Color)] = [
        ("pageBackground", .pageBackground), ("surface", .surface), ("surfaceMuted", .surfaceMuted), ("stage", .stage),
        ("outline", .outline), ("outlineStrong", .outlineStrong), ("textPrimary", .textPrimary), ("textSecondary", .textSecondary),
        ("textTertiary", .textTertiary), ("accent", .accent), ("accentText", .accentText), ("accentSoft", .accentSoft),
        ("highlight", .highlight), ("highlightSoft", .highlightSoft), ("success", .success), ("warning", .warning),
        ("danger", .danger), ("keep", .keep), ("send", .send), ("letGo", .letGo), ("toss", .toss), ("unsure", .unsure),
        ("undecided", .undecided), ("host", .host), ("guest", .guest),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Size.catalogueTileMin), spacing: Space.s)], spacing: Space.s) {
            ForEach(swatches, id: \.0) { name, colour in
                HStack(spacing: Space.s) {
                    RoundedRectangle(cornerRadius: Radius.xs).fill(colour)
                        .frame(width: Size.tick, height: Size.tick)
                        .overlay(RoundedRectangle(cornerRadius: Radius.xs).strokeBorder(Color.outline))
                    Text(name).font(.captionText).foregroundStyle(Color.textSecondary)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
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
        }
    }
}

private struct SpacingSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach([("xs", Space.xs), ("s", Space.s), ("m", Space.m), ("l", Space.l), ("xl", Space.xl), ("xxl", Space.xxl)], id: \.0) { name, value in
                HStack {
                    Text(name).font(.captionText).frame(width: Size.tapTarget, alignment: .leading)
                    Rectangle().fill(Color.accent).frame(width: value, height: Space.s)
                }
            }
            HStack(spacing: Space.s) {
                ForEach([Radius.xs, Radius.s, Radius.control, Radius.m, Radius.l], id: \.self) { r in
                    RoundedRectangle(cornerRadius: r).fill(Color.surface).frame(width: Size.thumbnail, height: Size.thumbnail)
                        .overlay(RoundedRectangle(cornerRadius: r).strokeBorder(Color.outlineStrong))
                }
            }
        }
    }
}

struct ButtonSamples: View {
    var body: some View {
        VStack(spacing: Space.s) {
            ForEach(AppButtonStyle.Role.allCases, id: \.self) { role in
                HStack(spacing: Space.s) {
                    Button("\(String(describing: role))") {}.buttonStyle(.app(role))
                    Button("Pressed") {}.buttonStyle(AppButtonStyle(role: role, previewPressed: true))
                }
            }
            HStack(spacing: Space.s) {
                Button { } label: { Label("Compact", systemImage: "plus") }.buttonStyle(.app(.primary, size: .compact, width: .hug))
                Button("Disabled") {}.buttonStyle(.app(.primary, size: .compact, width: .hug)).disabled(true)
                Button("Hug") {}.buttonStyle(.app(.neutral, size: .compact, width: .hug))
            }
        }
    }
}

private struct LinkSamples: View {
    var body: some View {
        HStack(spacing: Space.l) {
            Button { } label: { Label("Add something", systemImage: "plus") }.buttonStyle(.link)
            Button("Remove") {}.buttonStyle(.link(.destructive))
            Button("Disabled") {}.buttonStyle(.link).disabled(true)
            IconButton(symbol: "arrow.left", label: "Move left", filled: true) {}
            IconButton(symbol: "trash", label: "Remove", role: .destructive) {}
        }
    }
}

struct SelectionSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                AppChip(title: "Study", isSelected: true) {}
                AppChip(title: "Guest room", isSelected: false) {}
                AppChip(title: "Box room", detail: "7′ 10″ × 9′ 2″", isSelected: false) {}
            }
            AppChip(title: "Disabled", isSelected: false) {}.disabled(true)
            PickRow(title: "Yes, there are items", isSelected: true) {}
            PickRow(title: "No, the room is empty", subtitle: "You can add things later", isSelected: false) {}
            HStack { TickBadge(isOn: true); TickBadge(isOn: false) }
        }
    }
}

struct TagSamples: View {
    var body: some View {
        FlowLayout(spacing: Space.xs) {
            AppTag(kind: .neutral, text: "Shared")
            AppTag(kind: .highlight, text: "Highlight")
            AppTag(kind: .suggestion, text: "Alex: keep")
            ForEach(ItemStatus.decisions, id: \.self) { AppTag(kind: .decision($0), text: $0.statusLabel) }
            AppTag(kind: .owner(.host), text: "Linda’s")
            AppTag(kind: .owner(.guest), text: "Alex’s")
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
                DecisionButton(decision: d, isSelected: d == .keep, layout: .compact) {}
            }
            ForEach(ItemStatus.decisions, id: \.self) { d in
                DecisionButton(decision: d, detail: d.detail, isSelected: d == .letGo, layout: .full) {}
            }
            DecisionButton(decision: .toss, layout: .compact, suggesting: true) {}.disabled(true).opacity(Opacity.disabled)
        }
    }
}

private struct NoteSamples: View {
    var body: some View {
        VStack(spacing: Space.s) {
            NoteBar(text: "Alex suggests: keep") { Button("Use it") {} }
            NoteBar(text: "1 placement needs a look", symbol: "exclamationmark.triangle", tone: .warning)
            KVRow(label: "Room code", value: "K7M2Q", valueFont: .codeSmall) { Button("Copy") {}.buttonStyle(.link) }
            ChoiceTile(title: "Take a photo", detail: "Opens your camera", symbol: "camera")
            Text("Card").card()
            Text("Raised card").card(.raised)
        }
    }
}

private struct RoomCardSamples: View {
    var body: some View {
        VStack(spacing: Space.l) {
            ForEach(RoomCard.Tint.allCases, id: \.self) { tint in
                RoomCard(name: "Alex’s old room", plannedUse: "Study", status: "4 waiting for Alex, 1 for you", tint: tint)
            }
        }
    }
}

private struct BadgeSamples: View {
    var body: some View {
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
    }
}

// MARK: - Previews: every group in light, dark and large text

private struct PreviewStates<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                content
                content.padding(Space.m).background(Color.pageBackground).environment(\.colorScheme, .dark)
                content.dynamicTypeSize(.accessibility2)
            }
            .pagePadding()
        }
        .background(Color.pageBackground)
    }
}

#Preview("Gallery") { DesignSystemGallery() }
#Preview("Gallery · dark") { DesignSystemGallery().preferredColorScheme(.dark) }
#Preview("Gallery · large text") { DesignSystemGallery().dynamicTypeSize(.accessibility3) }
#Preview("Buttons") { PreviewStates { ButtonSamples(); LinkSamples() } }
#Preview("Selection") { PreviewStates { SelectionSamples() } }
#Preview("Tags") { PreviewStates { TagSamples() } }
#Preview("Decisions") { PreviewStates { DecisionSamples() } }
#Preview("Notes and rows") { PreviewStates { NoteSamples() } }
#Preview("Room cards") { PreviewStates { RoomCardSamples() } }
#Preview("Badges") { PreviewStates { BadgeSamples() } }
#Preview("Colours") { PreviewStates { ColourSwatches() } }
#Preview("Type") { PreviewStates { TypeSamples() } }
#endif
