import Foundation

/// JSON settings shared by PostgREST calls and Realtime payloads.
/// Swift camelCase ⇄ Postgres snake_case; dates as ISO 8601 with fractional seconds.
enum JSONCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(PostgresDate.string(from: date))
        }
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            guard let date = PostgresDate.date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unreadable date \(raw)")
            }
            return date
        }
        return d
    }()
}

/// Postgres sends timestamps like "2026-11-08T12:34:56.123456+00:00" (6 fractional digits),
/// which ISO8601DateFormatter can't always read, so we trim to milliseconds first.
enum PostgresDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(from date: Date) -> String { withFraction.string(from: date) }

    static func date(from raw: String) -> Date? {
        var s = raw.replacingOccurrences(of: " ", with: "T")
        if let dot = s.firstIndex(of: ".") {
            let afterDot = s.index(after: dot)
            let end = s[afterDot...].firstIndex { $0 == "+" || $0 == "-" || $0 == "Z" } ?? s.endIndex
            let millis = String((String(s[afterDot..<end]) + "000").prefix(3))
            s = String(s[..<dot]) + "." + millis + String(s[end...])
        }
        if s.hasSuffix("+00") { s += ":00" }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }
}

/// Encodes `nil` as JSON `null` instead of leaving the key out, so clearing a value
/// (e.g. undoing a decision) actually clears it on the server during an upsert.
@propertyWrapper
struct NullCodable<Value: Codable>: Codable {
    var wrappedValue: Value?

    init(wrappedValue: Value?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        wrappedValue = c.decodeNil() ? nil : try c.decode(Value.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let wrappedValue { try c.encode(wrappedValue) } else { try c.encodeNil() }
    }
}

extension KeyedDecodingContainer {
    /// Lets a missing key decode to nil for `@NullCodable` properties.
    func decode<T>(_ type: NullCodable<T>.Type, forKey key: Key) throws -> NullCodable<T> {
        try decodeIfPresent(type, forKey: key) ?? NullCodable(wrappedValue: nil)
    }
}
