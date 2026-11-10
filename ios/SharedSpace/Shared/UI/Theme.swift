import SwiftUI
import UIKit

// The one source of truth for how Shared Space looks (see ios/DESIGN_SYSTEM.md). Every colour, type
// style, size, radius, spacing value, stroke and shadow lives here or in the asset catalog;
// components and screens only read these names. Change a value here and the whole app follows.
//
// Colours are named colour sets in Assets.xcassets/Colors, each with light, dark and Increase
// Contrast variants. Tokens are named by role, not by colour, so the palette can be swapped.

private extension Color {
    static func token(_ name: String) -> Color { Color(name, bundle: .main) }
}

// MARK: - Colours by role

extension Color {
    // Surfaces
    /// Cards, buttons, sheets (White).
    static let surface = token("surface")
    /// Card fill when the background is white (Mist). Also behind photos, plans and the 3D room.
    static let surfaceMuted = token("surfaceMuted")
    /// Behind photos, plans and the 3D room.
    static let stage = surfaceMuted
    /// Progress tracks and pressed buttons (Cloud).
    static let track = token("track")
    /// Progress tracks on Mist cards.
    static let trackOnMuted = token("trackOnMuted")
    /// Button and chip outlines, 1.5 pt. Decorative: the label carries the meaning.
    static let outline = token("outline")
    /// Outlines that must be seen (text fields, tick rings): 3:1 or more on white.
    static let outlineStrong = token("outlineStrong")
    /// Decorative lines only.
    static let divider = token("divider")

    // Text
    static let textPrimary = token("textPrimary")
    /// Secondary text. Nothing lighter is ever used for text.
    static let textSecondary = token("textSecondary")

    // Brand
    /// Brand areas. Only `onBrand` text on it.
    static let brand = token("brand")
    static let onBrand = token("onBrand")
    /// Icons and neutral button labels on light backgrounds (Deep brown).
    static let iconNeutral = token("iconNeutral")
    /// Main accent: primary icons and labels, progress fill, Keep, the floating action circle.
    /// As text, only on white or Mist (it's an icon colour on the page gradient).
    static let accent = token("accent")
    /// Icons and text on an `accent` fill.
    static let onAccent = token("onAccent")
    static let tintBrown = token("tintBrown")
    static let tintSage = token("tintSage")
    static let tintSlate = token("tintSlate")
    static let tintBrick = token("tintBrick")

    // Decisions (always shown with an icon and a word too)
    static let keep = accent
    static let send = token("send")
    static let letGo = token("letGo")
    /// Destructive actions (removing an item, deleting a room).
    static let danger = letGo

    /// Number badges on photos: always white with ink text, whatever the colour scheme.
    static let photoBadge = token("photoBadge")
    static let onPhotoText = token("onPhoto")

    // Logo
    static let logoPrimary = brand
    static let logoSecondary = accent
    static let logoOverlap = textPrimary

    // 3D room materials
    static let roomWall = token("roomWall")
    static let roomFloor = token("roomFloor")
    static let roomWindow = token("roomWindow")
    static let roomDoor = token("roomDoor")

    /// Shadow colour for every elevation (Ink).
    static let shadowBase = token("shadow")

    /// An item's or catalogue piece's material colour. These are data (what the thing looks like),
    /// stored with the item or piece, not part of the app's styling.
    static func material(_ hex: String) -> Color {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xB9B2A6
        return Color(uiColor: UIColor(hex: value))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Tones: selected states and tags (soft 135° gradient, darker text, thin matching outline)

enum Tone: CaseIterable, Hashable {
    case sage, slate, brick, brown

    private var name: String {
        switch self {
        case .sage: "Sage"
        case .slate: "Slate"
        case .brick: "Brick"
        case .brown: "Brown"
        }
    }

    /// Text and icons on the tone's gradient.
    var text: Color { .token("tone\(name)Text") }
    var start: Color { .token("tone\(name)Start") }
    var end: Color { .token("tone\(name)End") }
    /// Outline for selected buttons only.
    var line: Color { .token("tone\(name)Line") }
    var fill: LinearGradient { LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing) }

    /// The tone's strong colour, for icons on white.
    var icon: Color {
        switch self {
        case .sage: .accent
        case .slate: .send
        case .brick: .letGo
        case .brown: .iconNeutral
        }
    }

    /// Flat tint for icon circles and tiles.
    var tint: Color {
        switch self {
        case .sage: .tintSage
        case .slate: .tintSlate
        case .brick: .tintBrick
        case .brown: .tintBrown
        }
    }
}

// MARK: - Page background (a single setting: switch the whole app between the two gradients)

enum PageBackground: CaseIterable, Hashable {
    case brown, sage

    var gradient: LinearGradient {
        let (top, middle, bottom): (String, String, String) = switch self {
        case .brown: ("backgroundBrownTop", "backgroundBrownMiddle", "backgroundBrownBottom")
        case .sage: ("backgroundSageTop", "backgroundSageMiddle", "backgroundSageBottom")
        }
        return LinearGradient(stops: [.init(color: .token(top), location: 0),
                                      .init(color: .token(middle), location: 0.45),
                                      .init(color: .token(bottom), location: 1)],
                              startPoint: .top, endPoint: .bottom)
    }

    /// The gradient's last stop, for bars pinned to the bottom of a screen.
    var bottom: Color { .token(self == .brown ? "backgroundBrownBottom" : "backgroundSageBottom") }
}

enum Theme {
    /// The background on every main screen. Change this to `.sage` to switch the whole app.
    static let background: PageBackground = .brown
    /// The tints room cards rotate through.
    static let roomTints: [Tone] = [.sage, .brown, .slate]
}

// MARK: - Spacing, radii, sizes, strokes

/// Spacing steps: 4, 8, 12, 16, 20, 24, 32.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    /// Screen side padding.
    static let page: CGFloat = 24
}

/// Buttons, chips and tags are capsules (`Capsule()`), so they have no radius here.
enum Radius {
    /// Lines and corners inside drawings (floor plan pieces, pin labels).
    static let drawing: CGFloat = 6
    /// Small pictures: item thumbnails, photo strip.
    static let thumb: CGFloat = 12
    /// Tiles, text fields, notes, choice rows.
    static let tile: CGFloat = 20
    /// Cards and list groups.
    static let card: CGFloat = 24
    /// Big cards: room cards, photos, plans.
    static let cardLarge: CGFloat = 28
    /// Sheets.
    static let sheet: CGFloat = 32
}

enum Size {
    /// The smallest tappable size (44 × 44).
    static let tapTarget: CGFloat = 44
    /// Main buttons and text fields.
    static let control: CGFloat = 52
    /// List rows.
    static let row: CGFloat = 60
    /// Tags.
    static let tag: CGFloat = 32
    /// Tick circles.
    static let tick: CGFloat = 26
    static let pin: CGFloat = 30
    /// Tinted icon circles (decision buttons, choice tiles).
    static let iconCircle: CGFloat = 40
    static let backButton: CGFloat = 48
    /// Floating action button height, and the accent circle inside it.
    static let floatingButton: CGFloat = 60
    static let floatingButtonIcon: CGFloat = 44
    /// Room card picture tile.
    static let roomTile: CGFloat = 88
    static let thumbnail: CGFloat = 52
    static let thumbnailLarge: CGFloat = 72
    static let avatar: CGFloat = 36
    static let progressBar: CGFloat = 8
    static let switchTrack = CGSize(width: 52, height: 32)
    /// Gap between the switch's knob and its track.
    static let switchKnobInset: CGFloat = 3
    /// The online dot, as a share of the avatar's size.
    static let onlineDotRatio: CGFloat = 0.32
    static let photoStrip = CGSize(width: 64, height: 52)
    /// Longest side of a room photo kept on disk and uploaded.
    static let photoUpload: CGFloat = 1600
    static let cardImageMax: CGFloat = 260
    static let previewImageMax: CGFloat = 200
    static let catalogueTileMin: CGFloat = 150
    static let numberFieldMax: CGFloat = 120
    static let brandMark: CGFloat = 28
    static let badgeSmall: CGFloat = 20
    /// Width of the icon column in rows, so labels line up.
    static let iconColumn: CGFloat = 24
    /// Extra bottom padding so lists scroll fully clear of the floating button or tab bar.
    static let floatingClearance: CGFloat = floatingButton + Space.xl * 2
}

/// Letter spacing for room codes (SF Pro's I and l look alike).
enum Tracking {
    static let code: CGFloat = 6
}

/// Fixed transparencies by role.
enum Opacity {
    static let disabled: Double = 0.4
    static let offline: Double = 0.45
    /// Rugs drawn on the floor plan.
    static let rugFill: Double = 0.25
    /// Freed-up zones on the floor plan.
    static let zoneFill: Double = 0.5
    static let zoneFillSelected: Double = 1
    static let pinLabel: Double = 0.86
    /// Where the logo's two squares overlap.
    static let logoOverlap: Double = 0.55
}

enum Stroke {
    static let hairline: CGFloat = 1
    /// Button, chip and field outlines.
    static let regular: CGFloat = 1.5
    static let bold: CGFloat = 2
    static let heavy: CGFloat = 3
    /// Dashes for new pieces, things that are leaving, and free space.
    static let dashed: [CGFloat] = [6, 5]
    static let dotted: [CGFloat] = [3, 4]
}

/// Shadows: two layers of Ink. Cards on white or Mist get no shadow (they use a Mist fill instead).
enum Elevation {
    case card, floating

    var layers: [(opacity: Double, radius: CGFloat, y: CGFloat)] {
        // Design values are blur sizes; SwiftUI's radius is half the blur.
        switch self {
        case .card: [(0.06, 1, 1), (0.07, 9, 6)]
        case .floating: [(0.06, 1, 1), (0.14, 9, 6)]
        }
    }
}

extension View {
    func elevation(_ e: Elevation, _ on: Bool = true) -> some View {
        let l = e.layers
        return self
            .shadow(color: on ? Color.shadowBase.opacity(l[0].opacity) : .clear, radius: l[0].radius, y: l[0].y)
            .shadow(color: on ? Color.shadowBase.opacity(l[1].opacity) : .clear, radius: l[1].radius, y: l[1].y)
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

// SF Pro through Dynamic Type text styles, so everything scales with the iPhone's text size.
// Semibold for screen and section titles and big numbers; medium for buttons, names, labels and
// tags; regular for everything else. Never thin or light.

extension Font {
    /// Large title (34 pt).
    static let largeTitleText = Font.system(.largeTitle, design: .default, weight: .semibold)
    /// Title: big titles on a screen ("Which room are we changing?", an item's name on a card). 22 pt.
    static let screenTitle = Font.system(.title2, design: .default, weight: .semibold)
    /// Section and sheet headings ("Add furniture", an item's name in its sheet). 20 pt.
    static let sectionTitle = Font.system(.title3, design: .default, weight: .semibold)
    /// Headline: card titles, room names. 20 pt medium.
    static let cardTitle = Font.system(.title3, design: .default, weight: .medium)
    static let bodyText = Font.body
    /// Names and labels at body size.
    static let bodyStrong = Font.body.weight(.medium)
    /// Secondary text (16 pt).
    static let detail = Font.callout
    /// Labels and tags at secondary size.
    static let detailStrong = Font.callout.weight(.medium)
    /// Main button labels.
    static let button = Font.body.weight(.medium)
    /// Compact button labels.
    static let buttonCompact = Font.callout.weight(.medium)
    /// Numbers inside small badges and labels drawn on plans and photos (graphics, not text runs).
    static let badge = Font.footnote.weight(.medium)
    /// The room code (a big number).
    static let code = Font.largeTitle.weight(.semibold)
    static let codeSmall = Font.title2.weight(.semibold)

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
    static func planLabel(fitting width: CGFloat) -> Font { .system(size: min(12, max(8, width / 7)), weight: .medium) }

    static func glyph(_ g: Glyph) -> Font { .system(size: g.size, weight: .regular) }
    /// A glyph sized to fit a component of `side` points (avatars, thumbnails).
    static func glyph(fitting side: CGFloat, ratio: CGFloat = 0.42, weight: Font.Weight = .regular) -> Font {
        .system(size: side * ratio, weight: weight)
    }
}

// MARK: - People

extension Role {
    /// Avatar and owner-tag tone.
    var tone: Tone { self == .host ? .sage : .brown }
}
