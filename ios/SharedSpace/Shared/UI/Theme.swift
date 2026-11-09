import SwiftUI
import UIKit

// The one source of truth for how Shared Space looks. Every colour, type style, size, radius,
// spacing value, stroke and shadow lives here; components and screens only read these names.
// Change a value here and the whole app follows. Values come from sharedSpaceCharline7.html.

// MARK: - Palette (raw values: only used inside this file)

private enum Palette {
    // Neutrals: warm cream paper, white cards, ink text.
    static let cream = (light: 0xF5F0E8 as UInt32, dark: 0x141A17 as UInt32)
    static let paper = (light: 0xFFFFFF as UInt32, dark: 0x1D2521 as UInt32)
    static let linen = (light: 0xECE6DB as UInt32, dark: 0x27312C as UInt32)
    static let sand = (light: 0xE5E3D8 as UInt32, dark: 0x1A211D as UInt32)
    static let hairline = (light: 0xE6DFD3 as UInt32, dark: 0x33403A as UInt32)
    static let pencil = (light: 0xC9C2B6 as UInt32, dark: 0x46544D as UInt32)
    static let ink = (light: 0x1D2A25 as UInt32, dark: 0xEDF1EC as UInt32)
    static let slate = (light: 0x45504A as UInt32, dark: 0xC4CCC6 as UInt32)
    static let stone = (light: 0x6B726D as UInt32, dark: 0x98A29B as UInt32)
    // Sage: the working accent.
    static let sage = (light: 0x44614D as UInt32, dark: 0x4F7359 as UInt32)
    static let sageText = (light: 0x44614D as UInt32, dark: 0x9CC2A8 as UInt32)
    static let sageMist = (light: 0xDEE6D6 as UInt32, dark: 0x22382F as UInt32)
    static let sageDeep = (light: 0x22342A as UInt32, dark: 0xCFE3D4 as UInt32)
    // Gold: highlights (status pills, the share/invite actions, new pieces in a plan).
    static let gold = (light: 0xC99A4E as UInt32, dark: 0xD4A95E as UInt32)
    static let goldInk = (light: 0x2A1C04 as UInt32, dark: 0x2A1C04 as UInt32)
    static let goldMist = (light: 0xF3E8D2 as UInt32, dark: 0x3A2F17 as UInt32)
    // Decisions.
    static let green = (light: 0x3B8659 as UInt32, dark: 0x62B584 as UInt32)
    static let greenMist = (light: 0xDCEEE2 as UInt32, dark: 0x1E3328 as UInt32)
    static let teal = (light: 0x2E8A8A as UInt32, dark: 0x5FC1BF as UInt32)
    static let tealMist = (light: 0xD8EEEE as UInt32, dark: 0x1B3434 as UInt32)
    static let blue = (light: 0x4767CF as UInt32, dark: 0x7E9AF0 as UInt32)
    static let blueMist = (light: 0xE1E7FA as UInt32, dark: 0x1F2946 as UInt32)
    static let brick = (light: 0xD4664A as UInt32, dark: 0xEE8B6F as UInt32)
    static let brickMist = (light: 0xF7E0D9 as UInt32, dark: 0x3D2620 as UInt32)
    static let grey = (light: 0x6B726D as UInt32, dark: 0xA3AAA5 as UInt32)
    static let greyMist = (light: 0xECE6DB as UInt32, dark: 0x2C332F as UInt32)
    static let ochre = (light: 0x9A6A12 as UInt32, dark: 0xE0B25E as UInt32)
    static let ochreMist = (light: 0xF5E8C8 as UInt32, dark: 0x3A2F17 as UInt32)
    static let pebble = (light: 0x9A9E98 as UInt32, dark: 0x7E867F as UInt32)
    /// Number badges on photos: always white with ink text, whatever the colour scheme.
    static let photoBadge = Color(Palette.white)
    static let onPhotoText = Color(light: 0x1D2A25, dark: 0x1D2A25)

    // People.
    static let forest = (light: 0x2E5A49 as UInt32, dark: 0x2E5A49 as UInt32)
    static let forestMist = (light: 0xDCE8E2 as UInt32, dark: 0x22382F as UInt32)
    static let marigold = (light: 0xE7A33A as UInt32, dark: 0xE7A33A as UInt32)
    static let marigoldMist = (light: 0xFBE8C6 as UInt32, dark: 0x3A2F17 as UInt32)
    static let marigoldInk = (light: 0x2B1D00 as UInt32, dark: 0x2B1D00 as UInt32)
    static let white = (light: 0xFFFFFF as UInt32, dark: 0xFFFFFF as UInt32)
    static let online = (light: 0x43B06C as UInt32, dark: 0x43B06C as UInt32)
    // The logo.
    static let logoGreen = (light: 0x2E5A49 as UInt32, dark: 0x2E5A49 as UInt32)
    static let logoGold = (light: 0xF0B03C as UInt32, dark: 0xF0B03C as UInt32)
    static let logoShade = (light: 0x1D2A25 as UInt32, dark: 0x1D2A25 as UInt32)
    // 3D room.
    static let wall = (light: 0xEFE9DF as UInt32, dark: 0xEFE9DF as UInt32)
    static let floorWood = (light: 0xC9A178 as UInt32, dark: 0xC9A178 as UInt32)
    static let glass = (light: 0x9CC3D5 as UInt32, dark: 0x9CC3D5 as UInt32)
    static let doorPanel = (light: 0xF6F2EA as UInt32, dark: 0xF6F2EA as UInt32)
}

private extension Color {
    init(_ pair: (light: UInt32, dark: UInt32)) { self.init(light: pair.light, dark: pair.dark) }
}

// MARK: - Colours by role

extension Color {
    // Surfaces
    /// The page behind everything.
    static let pageBackground = Color(Palette.cream)
    /// Cards, sheets, list groups.
    static let surface = Color(Palette.paper)
    /// Quiet fills: unselected segments, decision buttons, image placeholders.
    static let surfaceMuted = Color(Palette.linen)
    /// Behind room photos and plans.
    static let stage = Color(Palette.sand)
    static let outline = Color(Palette.hairline)
    static let outlineStrong = Color(Palette.pencil)

    // Text
    static let textPrimary = Color(Palette.ink)
    static let textSecondary = Color(Palette.slate)
    static let textTertiary = Color(Palette.stone)

    // Accent: primary actions, selection, links
    static let accent = Color(Palette.sage)
    /// Text and icons on `accent`.
    static let onAccent = Color(Palette.white)
    /// Accent used as text on the page (links, text actions).
    static let accentText = Color(Palette.sageText)
    static let accentSoft = Color(Palette.sageMist)
    /// Text on `accentSoft`.
    static let onAccentSoft = Color(Palette.sageDeep)

    // Highlight: status pills, share and invite, new pieces in a plan
    static let highlight = Color(Palette.gold)
    static let onHighlight = Color(Palette.goldInk)
    static let highlightSoft = Color(Palette.goldMist)

    // Feedback
    static let success = Color(Palette.green)
    static let successSoft = Color(Palette.greenMist)
    static let warning = Color(Palette.ochre)
    static let warningSoft = Color(Palette.ochreMist)
    static let danger = Color(Palette.brick)
    static let dangerSoft = Color(Palette.brickMist)
    static let online = Color(Palette.online)

    // Decisions (always shown with an icon and words too)
    static let keep = Color(Palette.green)
    static let keepSoft = Color(Palette.greenMist)
    static let moveElsewhere = Color(Palette.teal)
    static let moveElsewhereSoft = Color(Palette.tealMist)
    static let send = Color(Palette.blue)
    static let sendSoft = Color(Palette.blueMist)
    static let letGo = Color(Palette.brick)
    static let letGoSoft = Color(Palette.brickMist)
    static let toss = Color(Palette.grey)
    static let tossSoft = Color(Palette.greyMist)
    static let unsure = Color(Palette.ochre)
    static let unsureSoft = Color(Palette.ochreMist)
    static let undecided = Color(Palette.pebble)

    /// Number badges on photos: always white with ink text, whatever the colour scheme.
    static let photoBadge = Color(Palette.white)
    static let onPhotoText = Color(light: 0x1D2A25, dark: 0x1D2A25)

    // People
    static let host = Color(Palette.forest)
    static let hostSoft = Color(Palette.forestMist)
    static let onHost = Color(Palette.white)
    static let guest = Color(Palette.marigold)
    static let guestSoft = Color(Palette.marigoldMist)
    static let onGuest = Color(Palette.marigoldInk)

    // Logo
    static let logoPrimary = Color(Palette.logoGreen)
    static let logoSecondary = Color(Palette.logoGold)
    static let logoOverlap = Color(Palette.logoShade)

    // 3D room materials
    static let roomWall = Color(Palette.wall)
    static let roomFloor = Color(Palette.floorWood)
    static let roomWindow = Color(Palette.glass)
    static let roomDoor = Color(Palette.doorPanel)

    /// Shadow colour for every elevation.
    static let shadowBase = Color(Palette.ink)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// An item's or catalogue piece's material colour. These are data (what the thing looks like),
    /// stored with the item or piece, not part of the app's styling.
    static func material(_ hex: String) -> Color { Color(hex: hex) }

    init(hex string: String) {
        let value = UInt32(string.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xB9B2A6
        self.init(uiColor: UIColor(hex: value))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }

    convenience init(hexString: String) {
        self.init(hex: UInt32(hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xB9B2A6)
    }
}

// MARK: - Spacing, radii, sizes, strokes

/// Spacing scale. Use these for padding and stack spacing.
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    /// Page margins and card padding.
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

enum Radius {
    /// Tags.
    static let xs: CGFloat = 6
    /// Thumbnails, segments.
    static let s: CGFloat = 10
    /// Inputs and buttons that aren't pills.
    static let control: CGFloat = 12
    /// Cards, list groups, rows.
    static let m: CGFloat = 16
    /// Photos, plans, room cards.
    static let l: CGFloat = 24
}

enum Size {
    /// The smallest tappable size (Apple's 44 points).
    static let tapTarget: CGFloat = 44
    /// Buttons and text fields.
    static let control: CGFloat = 50
    /// List rows.
    static let row: CGFloat = 60
    /// Tick circles, pin badges.
    static let tick: CGFloat = 26
    static let pin: CGFloat = 30
    static let iconTile: CGFloat = 34
    static let thumbnail: CGFloat = 52
    static let thumbnailLarge: CGFloat = 72
    static let avatar: CGFloat = 34
    static let progressBar: CGFloat = 5
    static let photoStrip = CGSize(width: 64, height: 52)
    /// Longest side of a room photo kept on disk and uploaded.
    static let photoUpload: CGFloat = 1600
    static let roomCardImage: CGFloat = 190
    static let cardImageMax: CGFloat = 260
    static let previewImageMax: CGFloat = 200
    static let catalogueTileMin: CGFloat = 150
    static let segmentedMax: CGFloat = 170
    static let numberFieldMax: CGFloat = 120
    static let brandMark: CGFloat = 28
    static let badgeSmall: CGFloat = 20
    /// Width of the icon column in rows, so labels line up.
    static let iconColumn: CGFloat = 24
}

/// Letter spacing for the room code.
enum Tracking {
    static let code: CGFloat = 4
}

/// Fixed transparencies by role.
enum Opacity {
    static let disabled: Double = 0.4
    static let pressed: Double = 0.85
    static let linkPressed: Double = 0.6
    /// Secondary text on an accent fill (a chip's detail).
    static let secondaryOnAccent: Double = 0.8
    static let offline: Double = 0.45
    /// Rugs drawn on the floor plan.
    static let rugFill: Double = 0.25
    /// Rugs placed in a plan.
    static let newRugFill: Double = 0.15
    static let zoneFill: Double = 0.15
    static let zoneFillSelected: Double = 0.35
    static let pinLabel: Double = 0.86
}

enum Stroke {
    static let hairline: CGFloat = 1
    static let regular: CGFloat = 1.5
    static let bold: CGFloat = 2
    static let heavy: CGFloat = 3
    /// Dashes for things that are leaving, hidden, or free space.
    static let dashed: [CGFloat] = [6, 5]
    static let dotted: [CGFloat] = [3, 4]
}

/// Shadows by role.
enum Elevation {
    case card, raised, floating, segment

    var color: Color {
        switch self {
        case .card: Color.shadowBase.opacity(0.06)
        case .raised: Color.shadowBase.opacity(0.08)
        case .floating: Color.shadowBase.opacity(0.22)
        case .segment: Color.shadowBase.opacity(0.08)
        }
    }

    var radius: CGFloat {
        switch self {
        case .card: 9
        case .raised: 10
        case .floating: 12
        case .segment: 3
        }
    }

    var y: CGFloat {
        switch self {
        case .card: 4
        case .raised: 4
        case .floating: 6
        case .segment: 1
        }
    }
}

extension View {
    func elevation(_ e: Elevation, _ on: Bool = true) -> some View {
        shadow(color: on ? e.color : .clear, radius: e.radius, y: e.y)
    }
}

enum Motion {
    static let quick = Animation.easeOut(duration: 0.12)
    static let standard = Animation.snappy(duration: 0.25)
    static let screen = Animation.snappy(duration: 0.3)
    static let banner = Animation.spring(duration: 0.35)
    static let bannerDuration: Duration = .seconds(3.6)
    static let pressedScale: CGFloat = 0.98
    static let dragScale: CGFloat = 1.25
}

// MARK: - Type

// The prototype uses one grotesk face (Hanken Grotesk). On iOS that's SF. Every style is a text
// style, so it follows Dynamic Type.

extension Font {
    /// Big titles on a screen ("Which room are we changing?", an item's name on a card).
    static let screenTitle = Font.system(.title, design: .default, weight: .semibold)
    /// Section and sheet headings ("Study", an item's name in its sheet).
    static let sectionTitle = Font.system(.title2, design: .default, weight: .semibold)
    /// Card titles and smaller headings.
    static let cardTitle = Font.system(.title3, design: .default, weight: .semibold)
    static let bodyText = Font.body
    static let bodyStrong = Font.body.weight(.semibold)
    /// Small text: secondary lines, labels.
    static let detail = Font.subheadline
    static let detailStrong = Font.subheadline.weight(.semibold)
    static let footnoteText = Font.footnote
    static let captionText = Font.caption
    static let captionStrong = Font.caption.weight(.semibold)
    /// The room code.
    static let code = Font.largeTitle.weight(.bold).monospaced()
    static let codeSmall = Font.title3.weight(.bold).monospaced()

    /// Symbol sizes for icons that stand in for pictures.
    enum Glyph {
        case small, medium, large, hero

        var size: CGFloat {
            switch self {
            case .small: 13
            case .medium: 34
            case .large: 40
            case .hero: 64
            }
        }
    }

    /// Labels drawn inside things on the floor plan: scale with the thing, within readable limits.
    static func planLabel(fitting width: CGFloat) -> Font { .system(size: min(12, max(8, width / 7))) }

    static func glyph(_ g: Glyph) -> Font { .system(size: g.size, weight: .regular) }
    /// A glyph sized to fit a component of `side` points (avatars, thumbnails).
    static func glyph(fitting side: CGFloat, ratio: CGFloat = 0.42, weight: Font.Weight = .regular) -> Font {
        .system(size: side * ratio, weight: weight)
    }
}

extension Role {
    var color: Color { self == .host ? .host : .guest }
    var softColor: Color { self == .host ? .hostSoft : .guestSoft }
    var onColor: Color { self == .host ? .onHost : .onGuest }
}
