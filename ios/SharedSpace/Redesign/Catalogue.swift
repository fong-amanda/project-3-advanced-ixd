import Foundation

/// A piece that can be placed in a plan: from the sample catalogue, a copy of something already in
/// the room, or one of your own pieces entered by size.
///
/// Placements store only `catalogId`, so the id carries everything needed to draw the piece:
///   "b1"                          sample catalogue piece
///   "existing|<item uuid>"        a thing already in the room (size from the item)
///   "custom|<name>|<w>|<d>|<h>"   your own piece, sizes in cm
struct CatalogPiece: Identifiable, Hashable {
    enum Source: Hashable { case catalogue, existing(UUID), custom }

    let id: String
    let category: Category
    let kind: ItemCategory
    let name: String
    let w: Double
    let d: Double
    let h: Double
    /// Sample price in dollars; 0 for your own things.
    let price: Int
    let style: String
    let colorHex: String
    var source: Source = .catalogue

    var isFlat: Bool { kind.isFlat }

    enum Category: String, CaseIterable, Hashable {
        case all, existing, custom, beds, seating, storage, tables, lighting, decor

        var label: String {
            switch self {
            case .all: "Everything"
            case .existing: "Already here"
            case .custom: "Your own"
            case .beds: "Beds"
            case .seating: "Seating"
            case .storage: "Storage"
            case .tables: "Tables & desks"
            case .lighting: "Lighting"
            case .decor: "Rugs & decor"
            }
        }
    }
}

enum Catalogue {
    /// Sample furniture with realistic sizes (cm), from the prototype. Prices are illustrative.
    static let pieces: [CatalogPiece] = [
        .init(id: "b1", category: .beds, kind: .bed, name: "Linnea single bed", w: 97, d: 207, h: 88, price: 299, style: "Light & airy", colorHex: "#E4DED2"),
        .init(id: "b2", category: .beds, kind: .bed, name: "Harbor double bed", w: 146, d: 206, h: 95, price: 549, style: "Warm wood", colorHex: "#C7B39A"),
        .init(id: "b3", category: .beds, kind: .bed, name: "Daybed with trundle", w: 98, d: 205, h: 80, price: 429, style: "Light & airy", colorHex: "#D9D2C4"),
        .init(id: "b4", category: .beds, kind: .sofa, name: "Fold-out sofa bed", w: 200, d: 95, h: 85, price: 699, style: "Soft modern", colorHex: "#8C9A86"),
        .init(id: "b5", category: .beds, kind: .bed, name: "Compact small double", w: 126, d: 196, h: 90, price: 379, style: "Soft modern", colorHex: "#A9B3BD"),
        .init(id: "s1", category: .seating, kind: .armchair, name: "Moss reading chair", w: 78, d: 82, h: 88, price: 249, style: "Soft modern", colorHex: "#7E8F6E"),
        .init(id: "s2", category: .seating, kind: .armchair, name: "Rattan lounge chair", w: 72, d: 76, h: 80, price: 249, style: "Warm wood", colorHex: "#C9A57B"),
        .init(id: "s3", category: .seating, kind: .sofa, name: "Two-seat sofa", w: 160, d: 88, h: 83, price: 599, style: "Soft modern", colorHex: "#B9A58E"),
        .init(id: "s4", category: .seating, kind: .bench, name: "End-of-bed bench", w: 120, d: 40, h: 46, price: 179, style: "Warm wood", colorHex: "#B8916A"),
        .init(id: "s5", category: .seating, kind: .pouf, name: "Knitted pouf", w: 50, d: 50, h: 40, price: 69, style: "Light & airy", colorHex: "#D7C7B0"),
        .init(id: "st1", category: .storage, kind: .dresser, name: "Six-drawer dresser", w: 140, d: 48, h: 78, price: 399, style: "Warm wood", colorHex: "#C9A57B"),
        .init(id: "st2", category: .storage, kind: .wardrobe, name: "Slim wardrobe", w: 80, d: 58, h: 190, price: 349, style: "Light & airy", colorHex: "#ECE6DC"),
        .init(id: "st3", category: .storage, kind: .wardrobe, name: "Double wardrobe", w: 120, d: 58, h: 200, price: 549, style: "Warm wood", colorHex: "#CDB08A"),
        .init(id: "st4", category: .storage, kind: .bookshelf, name: "Open shelf, 4 tier", w: 80, d: 30, h: 150, price: 99, style: "Warm wood", colorHex: "#D9C4A2"),
        .init(id: "st5", category: .storage, kind: .nightstand, name: "Oak bedside table", w: 40, d: 35, h: 50, price: 89, style: "Warm wood", colorHex: "#C9A57B"),
        .init(id: "st6", category: .storage, kind: .nightstand, name: "Two-drawer bedside", w: 45, d: 38, h: 55, price: 119, style: "Soft modern", colorHex: "#AEB7B0"),
        .init(id: "t1", category: .tables, kind: .desk, name: "Fold-down wall desk", w: 90, d: 45, h: 75, price: 149, style: "Light & airy", colorHex: "#E6DED0"),
        .init(id: "t2", category: .tables, kind: .desk, name: "Oak writing desk", w: 120, d: 60, h: 75, price: 129, style: "Warm wood", colorHex: "#B8916A"),
        .init(id: "c1", category: .seating, kind: .chair, name: "Mesh desk chair", w: 60, d: 60, h: 95, price: 89, style: "Soft modern", colorHex: "#3E4A45"),
        .init(id: "t3", category: .tables, kind: .sideTable, name: "Round side table", w: 45, d: 45, h: 55, price: 79, style: "Soft modern", colorHex: "#8C9590"),
        .init(id: "t4", category: .tables, kind: .table, name: "Narrow console table", w: 100, d: 35, h: 78, price: 189, style: "Warm wood", colorHex: "#A9845F"),
        .init(id: "l1", category: .lighting, kind: .lamp, name: "Linen floor lamp", w: 40, d: 40, h: 155, price: 119, style: "Light & airy", colorHex: "#F1E4C8"),
        .init(id: "l2", category: .lighting, kind: .lamp, name: "Tall reading lamp", w: 32, d: 32, h: 170, price: 159, style: "Soft modern", colorHex: "#E9D9B8"),
        .init(id: "d1", category: .decor, kind: .rug, name: "Wool rug 170 × 240", w: 170, d: 240, h: 1, price: 229, style: "Light & airy", colorHex: "#D8CFC0"),
        .init(id: "d2", category: .decor, kind: .rug, name: "Round jute rug", w: 150, d: 150, h: 1, price: 119, style: "Warm wood", colorHex: "#C8B48F"),
        .init(id: "d3", category: .decor, kind: .plant, name: "Fiddle-leaf fig", w: 45, d: 45, h: 150, price: 89, style: "Light & airy", colorHex: "#6E9A5E"),
        .init(id: "d4", category: .decor, kind: .mirror, name: "Full-length mirror", w: 50, d: 6, h: 170, price: 139, style: "Warm wood", colorHex: "#B8916A"),
        .init(id: "d5", category: .decor, kind: .other, name: "Luggage rack", w: 66, d: 40, h: 53, price: 79, style: "Warm wood", colorHex: "#B8916A"),
    ]

    private static let byId = Dictionary(uniqueKeysWithValues: pieces.map { ($0.id, $0) })

    /// Turns a placement's catalogId back into a piece. `items` resolves "existing|…" copies.
    static func piece(_ catalogId: String, items: [Item]) -> CatalogPiece? {
        if let p = byId[catalogId] { return p }
        let parts = catalogId.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if parts.first == "existing", parts.count == 2, let id = UUID(uuidString: parts[1]),
           let item = items.first(where: { $0.id == id }) {
            return existing(item)
        }
        if parts.first == "custom", parts.count == 5,
           let w = Double(parts[2]), let d = Double(parts[3]), let h = Double(parts[4]) {
            return CatalogPiece(id: catalogId, category: .custom, kind: .other, name: parts[1], w: w, d: d, h: h,
                                price: 0, style: "Your own", colorHex: "#B8A58C", source: .custom)
        }
        return nil
    }

    static func existing(_ item: Item) -> CatalogPiece {
        CatalogPiece(id: "existing|\(item.id.uuidString)", category: .existing, kind: item.category, name: item.name,
                     w: item.widthCm, d: item.depthCm, h: item.heightCm, price: 0, style: "Already here",
                     colorHex: item.category.colorHex, source: .existing(item.id))
    }

    static func customId(name: String, w: Double, d: Double, h: Double) -> String {
        let clean = name.replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces)
        return "custom|\(clean.isEmpty ? "Custom piece" : clean)|\(Int(w.rounded()))|\(Int(d.rounded()))|\(Int(h.rounded()))"
    }
}

// MARK: - Fit

/// A space to check pieces against (a freed-up zone, or dimensions typed in).
struct FitSpace: Equatable {
    var w: Double
    var d: Double
    var h: Double
}

enum Fit {
    case ok, tight, no

    var label: String {
        switch self {
        case .ok: "Fits floor"
        case .tight: "Tight fit"
        case .no: "Too big"
        }
    }

    /// Fits either way round; "tight" when less than 10 cm to spare.
    static func of(_ piece: CatalogPiece, in space: FitSpace) -> Fit {
        if piece.h > space.h { return .no }
        var best = -1.0
        for (w, d) in [(piece.w, piece.d), (piece.d, piece.w)] where w <= space.w && d <= space.d {
            best = max(best, min(space.w - w, space.d - d))
        }
        if best < 0 { return .no }
        return best < 10 ? .tight : .ok
    }
}

/// Floor that Sort freed up: the footprints of things leaving the room, merged where they touch.
struct FreeZone: Identifiable, Equatable {
    let id: Int
    let rect: FloorRect
    let label: String
}

enum FreeZones {
    static func compute(items: [Item], room: Room) -> [FreeZone] {
        let W = Double(room.widthCm), L = Double(room.lengthCm)
        var rects = items.filter { $0.status.leavesRoom && !$0.category.isFlat }.map(RoomGeometry.footprint(of:))
        var merged = true
        while merged {
            merged = false
            outer: for i in rects.indices {
                for j in rects.indices where j > i {
                    let a = rects[i], b = rects[j]
                    if FloorRect(x: a.x - 15, z: a.z - 15, w: a.w + 30, d: a.d + 30).overlaps(b) {
                        let x = min(a.x, b.x), z = min(a.z, b.z)
                        rects[i] = FloorRect(x: x, z: z, w: max(a.maxX, b.maxX) - x, d: max(a.maxZ, b.maxZ) - z)
                        rects.remove(at: j)
                        merged = true
                        break outer
                    }
                }
            }
        }
        return rects
            .map { r in
                let x = min(max(r.x, 0), W), z = min(max(r.z, 0), L)
                return FloorRect(x: x, z: z, w: min(r.w, W - x).rounded(), d: min(r.d, L - z).rounded())
            }
            .sorted { $0.w * $0.d > $1.w * $1.d }
            .enumerated()
            .map { FreeZone(id: $0, rect: $1, label: label(for: $1, W: W, L: L)) }
    }

    private static func label(for z: FloorRect, W: Double, L: Double) -> String {
        let cx = z.x + z.w / 2, cz = z.z + z.d / 2
        let h = cx < W * 0.34 ? "left" : cx > W * 0.66 ? "right" : "mid"
        let v = cz < L * 0.34 ? "back" : cz > L * 0.66 ? "front" : "mid"
        let names = [
            "back-left": "Back left corner", "back-mid": "Along the back wall", "back-right": "Back right corner",
            "mid-left": "Along the left wall", "mid-mid": "Middle of the room", "mid-right": "Along the right side",
            "front-left": "Front left corner", "front-mid": "Near the front", "front-right": "Front right corner",
        ]
        return names["\(v)-\(h)"] ?? "Free space"
    }
}
