import SwiftUI

/// What kind of thing an item is. Drives default size, colour, icon and 3D shape.
/// Ported from the prototype's KINDS table (sizes in cm).
enum ItemCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case desk, chair, armchair, sofa, bed, bookshelf, wardrobe, dresser, cabinet, nightstand
    case table, sideTable, lamp, plant, rug, boxes, exerciseBike, guitar, tvUnit, bench, pouf
    case mirror, television, appliance, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .desk: "Desk"
        case .chair: "Chair"
        case .armchair: "Armchair"
        case .sofa: "Sofa"
        case .bed: "Bed"
        case .bookshelf: "Bookshelf"
        case .wardrobe: "Wardrobe"
        case .dresser: "Chest of drawers"
        case .cabinet: "Cabinet"
        case .nightstand: "Bedside table"
        case .table: "Table"
        case .sideTable: "Side table"
        case .lamp: "Floor lamp"
        case .plant: "Plant"
        case .rug: "Rug"
        case .boxes: "Boxes"
        case .exerciseBike: "Exercise bike"
        case .guitar: "Guitar"
        case .tvUnit: "TV unit"
        case .bench: "Bench"
        case .pouf: "Pouf"
        case .mirror: "Mirror"
        case .television: "Television"
        case .appliance: "Appliance"
        case .other: "Something else"
        }
    }

    /// Default width × depth × height in cm, used for manually added items.
    var defaultSize: (w: Double, d: Double, h: Double) {
        switch self {
        case .desk: (140, 70, 75)
        case .chair: (62, 62, 100)
        case .armchair: (82, 82, 90)
        case .sofa: (190, 90, 85)
        case .bed: (100, 205, 90)
        case .bookshelf: (80, 30, 190)
        case .wardrobe: (100, 60, 200)
        case .dresser: (100, 48, 80)
        case .cabinet: (45, 60, 100)
        case .nightstand: (45, 38, 55)
        case .table: (120, 75, 75)
        case .sideTable: (45, 45, 55)
        case .lamp: (38, 38, 160)
        case .plant: (40, 40, 100)
        case .rug: (200, 140, 1)
        case .boxes: (70, 50, 80)
        case .exerciseBike: (110, 55, 130)
        case .guitar: (40, 15, 100)
        case .tvUnit: (160, 40, 50)
        case .bench: (120, 40, 46)
        case .pouf: (50, 50, 40)
        case .mirror: (50, 6, 170)
        case .television: (120, 8, 70)
        case .appliance: (60, 60, 85)
        case .other: (50, 50, 50)
        }
    }

    /// Flat things you can walk over: never block placement, never "free up" floor.
    var isFlat: Bool { self == .rug }

    var symbol: String {
        switch self {
        case .desk, .table, .sideTable: "table.furniture"
        case .chair, .armchair, .pouf, .bench: "chair.lounge"
        case .sofa: "sofa"
        case .bed: "bed.double"
        case .bookshelf: "books.vertical"
        case .wardrobe, .dresser, .cabinet, .nightstand, .tvUnit: "cabinet"
        case .lamp: "lamp.floor"
        case .plant: "leaf"
        case .rug: "square.dashed"
        case .boxes: "shippingbox"
        case .exerciseBike: "figure.indoor.cycle"
        case .guitar: "guitars"
        case .mirror: "rectangle.portrait"
        case .television: "tv"
        case .appliance: "washer"
        case .other: "cube"
        }
    }

    /// Base colour for the 3D block that stands in for a real item (hex).
    var colorHex: String {
        switch self {
        case .desk, .table, .sideTable, .bench, .mirror: "#B8916A"
        case .chair: "#3E4A45"
        case .armchair: "#7E8F6E"
        case .sofa: "#9B8B78"
        case .bed: "#C7B9A4"
        case .bookshelf: "#A7825C"
        case .wardrobe: "#E6E0D6"
        case .dresser, .nightstand: "#C9A57B"
        case .cabinet: "#9AA3A0"
        case .lamp: "#F1E4C8"
        case .plant: "#6E9A5E"
        case .rug: "#8FA3B5"
        case .boxes: "#C4986A"
        case .exerciseBike: "#475563"
        case .guitar: "#B5652F"
        case .tvUnit: "#8A6A4C"
        case .pouf: "#C9B49A"
        case .television: "#2B3330"
        case .appliance: "#DADDDB"
        case .other: "#B9B2A6"
        }
    }

    /// Categories offered when adding an item by hand.
    static let addable: [ItemCategory] = [
        .desk, .chair, .armchair, .sofa, .bed, .bookshelf, .wardrobe, .dresser, .cabinet, .nightstand,
        .table, .sideTable, .lamp, .plant, .rug, .boxes, .exerciseBike, .guitar, .tvUnit, .television, .other,
    ]

    /// Best guess from a free-text name ("old couch" → sofa). Ported from the prototype.
    static func guess(from name: String) -> ItemCategory {
        let n = name.lowercased()
        let map: [(String, ItemCategory)] = [
            ("desk", .desk), ("armchair", .armchair), ("office chair", .chair), ("chair", .chair),
            ("sofa", .sofa), ("couch", .sofa), ("bed", .bed), ("shelf", .bookshelf), ("book", .bookshelf),
            ("wardrobe", .wardrobe), ("closet", .wardrobe), ("drawer", .dresser), ("dresser", .dresser),
            ("cabinet", .cabinet), ("nightstand", .nightstand), ("bedside", .nightstand),
            ("side table", .sideTable), ("table", .table), ("lamp", .lamp), ("light", .lamp),
            ("plant", .plant), ("rug", .rug), ("carpet", .rug), ("box", .boxes), ("bike", .exerciseBike),
            ("treadmill", .exerciseBike), ("guitar", .guitar), ("tv unit", .tvUnit), ("tv", .television),
            ("bench", .bench), ("mirror", .mirror), ("pouf", .pouf), ("stool", .pouf),
        ]
        return map.first { n.contains($0.0) }?.1 ?? .other
    }
}
