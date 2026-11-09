import Foundation

/// How sizes are shown. Everything is stored in centimetres.
enum UnitSystem: String, CaseIterable, Sendable {
    case feet = "ft"
    case metric = "cm"

    var label: String { self == .feet ? "Feet & inches" : "Centimetres" }
    /// The unit people type in: inches or centimetres.
    var inputUnit: String { self == .feet ? "in" : "cm" }

    /// How far one tap of a − / + stepper moves: 3 inches or 10 cm.
    var stepCm: Double { self == .feet ? 7.62 : 10 }

    /// cm → the number shown in an input field (inches or cm).
    func input(fromCm cm: Double) -> Int { Int((self == .feet ? cm / 2.54 : cm).rounded()) }
    /// Number typed in an input field → cm.
    func cm(fromInput value: Double) -> Double { self == .feet ? value * 2.54 : value }

    /// A length: 3′ 4″, 85 cm (for furniture).
    func length(_ cm: Double) -> String {
        switch self {
        case .feet: Self.feetAndInches(cm)
        case .metric: "\(Int(cm.rounded())) cm"
        }
    }

    /// A room-sized length: 11′ 2″, 3.4 m.
    func roomLength(_ cm: Double) -> String {
        switch self {
        case .feet: Self.feetAndInches(cm)
        case .metric: (cm / 100).formatted(.number.precision(.fractionLength(0...2))) + " m"
        }
    }

    /// Furniture size: "3′ 4″ × 2′ 4″ × 2′ 6″" or "100 × 70 × 75 cm". Flat things (rugs) leave out the height.
    func dims(_ w: Double, _ d: Double, _ h: Double) -> String {
        let flat = h <= 4
        switch self {
        case .feet:
            return ([w, d] + (flat ? [] : [h])).map(Self.feetAndInches).joined(separator: " × ")
        case .metric:
            return ([w, d] + (flat ? [] : [h])).map { "\(Int($0.rounded()))" }.joined(separator: " × ") + " cm"
        }
    }

    /// Floor area from cm²: "38 sq ft" or "3.5 m²".
    func area(_ cm2: Double) -> String {
        switch self {
        case .feet: "\(Int((cm2 / 929.03).rounded())) sq ft"
        case .metric: String(format: "%.1f m²", cm2 / 10_000)
        }
    }

    private static func feetAndInches(_ cm: Double) -> String {
        let inches = cm / 2.54
        var feet = Int(inches / 12)
        var rest = Int((inches - Double(feet) * 12).rounded())
        if rest == 12 { feet += 1; rest = 0 }
        if feet == 0 { return "\(rest)″" }
        return rest == 0 ? "\(feet)′" : "\(feet)′ \(rest)″"
    }
}
