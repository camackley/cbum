import Foundation

// Utilidades de fecha. El cliente calcula el `date` (YYYY-MM-DD) en America/Bogota;
// `ts` es ISO-8601 con offset. El server no hace math de timezone (contracts §00).
enum CBDate {
    static let bogota = TimeZone(identifier: "America/Bogota") ?? .current

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = bogota
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = bogota
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func ts(_ date: Date = Date()) -> String { isoFormatter.string(from: date) }
    static func day(_ date: Date = Date()) -> String { dayFormatter.string(from: date) }
    static func date(fromDay day: String) -> Date? { dayFormatter.date(from: day) }
    static func date(fromTs ts: String) -> Date? { isoFormatter.date(from: ts) }

    static func nowMillis() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    /// Etiqueta corta en español: "Lun · 14 Jul".
    static func shortLabel(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.timeZone = bogota
        f.dateFormat = "EEE · d MMM"
        return f.string(from: date).capitalized
    }

    /// Etiqueta "14 jul" (es-CO) para lollipops de scrubbing (delta §R6).
    static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.timeZone = bogota
        f.dateFormat = "d MMM"
        return f
    }()
    static func dayMonth(_ date: Date) -> String { dayMonthFormatter.string(from: date) }

    /// Hora "13:20".
    static func hour(fromTs ts: String) -> String {
        guard let d = date(fromTs: ts) else { return "" }
        let f = DateFormatter(); f.timeZone = bogota; f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
