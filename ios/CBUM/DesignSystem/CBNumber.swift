import Foundation

// Formato numérico central de la app — `Locale es_CO` (delta §R6 / I6).
// Colombia usa "." para miles y "," para decimales: 1.830 kcal, 133,3 kg.
// TODA la UI (features + componentes) formatea aquí; los DTOs/API NO cambian
// (siguen siendo números JSON). Reemplaza los `String(format:)` e interpolaciones
// numéricas directas de las pantallas.
enum CBNumber {
    static let locale = Locale(identifier: "es_CO")

    // Formatters cacheados por nº de decimales (crear NumberFormatter es caro).
    private static var cache: [Int: NumberFormatter] = [:]
    private static func formatter(decimals: Int) -> NumberFormatter {
        if let f = cache[decimals] { return f }
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        cache[decimals] = f
        return f
    }

    /// "1.830", "133,3", "2.976". `decimals` fija los decimales mostrados.
    static func format(_ value: Double, decimals: Int = 0) -> String {
        formatter(decimals: decimals).string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Con signo explícito para deltas/ritmos: "+0,07", "-0,35", "0,00".
    static func signed(_ value: Double, decimals: Int = 2) -> String {
        let s = format(abs(value), decimals: decimals)
        if value > 0 { return "+" + s }
        if value < 0 { return "-" + s }
        return s
    }

    /// Entero "inteligente": sin decimales si es entero, si no `decimals`.
    static func smart(_ value: Double, decimals: Int = 1) -> String {
        value == value.rounded() ? format(value, decimals: 0) : format(value, decimals: decimals)
    }

    /// Porcentaje entero: "90%".
    static func percent(_ fraction: Double) -> String {
        format((fraction * 100).rounded(), decimals: 0) + "%"
    }
}
