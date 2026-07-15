import Foundation

// Macros por 100g (per_100g en contracts §1) y para totales/targets.
struct Macros: Codable, Equatable {
    var kcal: Double
    var protein_g: Double
    var carbs_g: Double
    var fat_g: Double
    var fiber_g: Double?

    static let zero = Macros(kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0)

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal,
               protein_g: a.protein_g + b.protein_g,
               carbs_g: a.carbs_g + b.carbs_g,
               fat_g: a.fat_g + b.fat_g,
               fiber_g: (a.fiber_g ?? 0) + (b.fiber_g ?? 0))
    }

    /// Escala per_100g por gramos: macros = per_100g × quantity_g / 100.
    /// Misma regla que el server al recalcular porción (contracts §3 PATCH).
    func scaled(toGrams grams: Double) -> Macros {
        let f = grams / 100.0
        return Macros(kcal: kcal * f, protein_g: protein_g * f,
                      carbs_g: carbs_g * f, fat_g: fat_g * f,
                      fiber_g: fiber_g.map { $0 * f })
    }
}
