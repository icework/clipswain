import Foundation

/// Shared coders matching the server's JSON conventions (camelCase keys, ISO-8601 dates
/// with or without fractional seconds).
public enum PaperclipJSON {
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseDate(raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: KitL10n.string("api.error.unrecognized_date", defaultValue: "Unrecognized date: \(raw)"))
        }
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter().string(from: date))
        }
        return encoder
    }()

    public static func parseDate(_ raw: String) -> Date? {
        if let date = fractionalFormatter().date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) { return date }
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        return dateOnly.date(from: raw)
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

/// A string-backed enum that keeps unknown server values instead of failing to decode,
/// so a newer server never breaks an older app.
public protocol OpenEnum: RawRepresentable, Codable, Hashable, Sendable, CaseIterable
where RawValue == String {
    static var fallback: Self { get }
}

extension OpenEnum {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }
}
