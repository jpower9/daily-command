import Foundation

/// A parsed JSON value. The API returns loosely typed rows (numbers that may be
/// strings, ids that may be numbers, optional fields), so responses are read
/// through this instead of strict Codable models that would drop a whole list
/// over one odd field.
public enum JSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public init(data: Data) throws {
        let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        self = JSON(any: raw)
    }

    public init(any: Any?) {
        switch any {
        case nil, is NSNull: self = .null
        case let n as NSNumber:
            // NSNumber bridges Bool too; CFBoolean is the only way to tell them apart.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { JSON(any: $0) })
        case let o as [String: Any]: self = .object(o.mapValues { JSON(any: $0) })
        default: self = .null
        }
    }

    /// Foundation form, for serialization.
    public var anyValue: Any {
        switch self {
        case .null: NSNull()
        case let .bool(b): b
        case let .number(n): n
        case let .string(s): s
        case let .array(a): a.map(\.anyValue)
        case let .object(o): o.mapValues(\.anyValue)
        }
    }

    public func data() throws -> Data {
        try JSONSerialization.data(withJSONObject: anyValue, options: [.fragmentsAllowed, .sortedKeys])
    }

    public subscript(key: String) -> JSON {
        if case let .object(o) = self { return o[key] ?? .null }
        return .null
    }

    public var string: String? {
        switch self {
        case let .string(s): s
        default: nil
        }
    }

    /// A string, or a number rendered as an integer string (ids can be either).
    public var idString: String? {
        switch self {
        case let .string(s): s
        case let .number(n): n == n.rounded() ? String(Int64(n)) : String(n)
        default: nil
        }
    }

    public var nonEmptyString: String? {
        guard let s = string, !s.isEmpty else { return nil }
        return s
    }

    public var double: Double? {
        switch self {
        case let .number(n): n
        case let .string(s): Double(s)
        default: nil
        }
    }

    public var int: Int? { double.map { Int($0) } }

    public var bool: Bool? {
        switch self {
        case let .bool(b): b
        default: nil
        }
    }

    public var array: [JSON] {
        if case let .array(a) = self { return a }
        return []
    }

    public var object: [String: JSON]? {
        if case let .object(o) = self { return o }
        return nil
    }

    public var isNull: Bool { self == .null }

    /// Back to Foundation types, for re-encoding.
    public var foundationValue: Any {
        switch self {
        case .null: NSNull()
        case let .bool(b): b
        case let .number(n): n
        case let .string(s): s
        case let .array(a): a.map(\.foundationValue)
        case let .object(o): o.mapValues(\.foundationValue)
        }
    }
}

/// ISO-8601 timestamps from Postgres arrive with or without fractional seconds.
public enum ServerDate {
    public static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let d = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return d }
        if let d = try? Date(string, strategy: Date.ISO8601FormatStyle()) { return d }
        // Postgres sometimes sends "2026-10-04 12:12:00+00" (space separator).
        let fixed = string.replacingOccurrences(of: " ", with: "T")
        if let d = try? Date(fixed, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return d }
        return try? Date(fixed, strategy: Date.ISO8601FormatStyle())
    }

    /// ISO 8601 with fractional seconds, as the service sends it.
    public static func string(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    /// `yyyy-MM-dd` in the device's calendar.
    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
