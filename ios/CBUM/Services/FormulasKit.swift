import Foundation

// FormulasKit — reproducción EXACTA de las fórmulas de contracts §5.
// Duplicación intencional y testeada del cálculo del server para que la app
// funcione offline con los MISMOS números. Ver FormulasKitTests.
// Sin dependencias de UI: Foundation puro (compilable/testeable standalone).
enum FormulasKit {

    // MARK: - §5.1 Tendencia de peso (EMA, α = 0.1)
    // ema_0 = w_0 ; ema_i = ema_{i-1} + 0.1·(w_i − ema_{i-1}).
    // Días sin pesaje: EMA no cambia (carry forward). nil antes del 1er pesaje.
    static let emaAlpha = 0.1

    static func ema(dailyWeights: [Double?]) -> [Double?] {
        var out: [Double?] = []
        var prev: Double? = nil
        for w in dailyWeights {
            if let w {
                if let p = prev {
                    prev = p + emaAlpha * (w - p)
                } else {
                    prev = w            // primer pesaje: ema_0 = w_0
                }
            }
            // sin pesaje: prev queda igual (carry forward)
            out.append(prev)
        }
        return out
    }

    /// Conveniencia: agrupa muestras crudas por día (America/Bogota, promediando
    /// múltiples pesajes del mismo día), llena el rango de días y devuelve la
    /// serie EMA por día `[(date, ema)]` (solo días con EMA definido).
    static func emaSeries(readings: [(date: Date, value: Double)],
                          calendar: Calendar = .bogota) -> [(date: Date, ema: Double)] {
        guard !readings.isEmpty else { return [] }
        // bucket por día
        var byDay: [Date: [Double]] = [:]
        for r in readings {
            let day = calendar.startOfDay(for: r.date)
            byDay[day, default: []].append(r.value)
        }
        let sortedDays = byDay.keys.sorted()
        guard let first = sortedDays.first, let last = sortedDays.last else { return [] }
        // construir arreglo día a día en el rango [first, last]
        var days: [Date] = []
        var cursor = first
        while cursor <= last {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        let dailyAvg: [Double?] = days.map { day in
            if let vals = byDay[day], !vals.isEmpty {
                return vals.reduce(0, +) / Double(vals.count)
            }
            return nil
        }
        let emas = ema(dailyWeights: dailyAvg)
        var result: [(Date, Double)] = []
        for (d, e) in zip(days, emas) {
            if let e { result.append((d, e)) }
        }
        return result
    }

    // MARK: - §5.3 e1RM (Epley ajustado por RIR)
    // e1rm = weight·(1 + (reps + rir)/30). Válido solo si !warmup y (reps+rir) ≤ 12.
    // Fuera de rango → nil (no se grafica ni cuenta para PR). Redondeo a 1 decimal.
    static func e1rm(weightKg: Double, reps: Int, rir: Int, isWarmup: Bool) -> Double? {
        guard !isWarmup, (reps + rir) <= 12 else { return nil }
        let raw = weightKg * (1.0 + Double(reps + rir) / 30.0)
        return (raw * 10).rounded() / 10
    }

    // MARK: - §5.4 Sugerencia de peso (doble progresión)
    enum SuggestionReason: String {
        case doubleProgressionIncrease = "double_progression_increase"
        case repeatWeight = "repeat_weight"
        case noHistory = "no_history"
    }

    struct WorkingSet {
        let weightKg: Double
        let reps: Int
        let rir: Int
        let isWarmup: Bool
    }

    struct Suggestion {
        let weightKg: Double?
        let reason: SuggestionReason
    }

    /// `lastSessionSets`: sets (cualquier tipo) de la última sesión que incluyó
    /// el ejercicio, en orden. Se filtran los de trabajo (is_warmup=0).
    /// `prescribedSets`: cuántos sets pide el programa — se exige que TODOS los
    /// sets prescritos se hayan cumplido (contracts §5.4). Si el programa no lo
    /// especifica, pásalo como 0 para no exigir mínimo.
    static func suggestWeight(lastSessionSets: [WorkingSet],
                              prescribedSets: Int,
                              repRangeMax: Int,
                              targetRIR: Int,
                              incrementKg: Double) -> Suggestion {
        let working = lastSessionSets.filter { !$0.isWarmup }
        guard let lastSet = working.last else {
            return Suggestion(weightKg: nil, reason: .noHistory)
        }
        let lastWeight = lastSet.weightKg   // peso del último set de trabajo
        // §5.4: TODOS los sets prescritos deben cumplir reps ≥ max y rir ≥ target.
        // Requiere además haber completado al menos los sets prescritos.
        let completedEnough = working.count >= prescribedSets
        let allMet = completedEnough && working.allSatisfy { $0.reps >= repRangeMax && $0.rir >= targetRIR }
        if allMet {
            return Suggestion(weightKg: lastWeight + incrementKg, reason: .doubleProgressionIncrease)
        } else {
            return Suggestion(weightKg: lastWeight, reason: .repeatWeight)
        }
    }

    // MARK: - §5.2 TDEE
    enum TDEEStatus: String { case adaptive, calibrating }

    struct TDEEResult {
        let kcal: Double
        let status: TDEEStatus
    }

    /// Adaptativo. `avgIntakeCompleteDays` = promedio kcal solo de días complete
    /// dentro de la ventana; `deltaEMA` = ema(último) − ema(primero) de la ventana;
    /// `windowDays` = 21. daily_balance = ΔEMA·7700/windowDays. TDEE = avg − balance.
    static func tdeeAdaptive(avgIntakeCompleteDays: Double,
                             deltaEMA: Double,
                             windowDays: Int = 21) -> Double {
        let dailyBalance = deltaEMA * 7700.0 / Double(windowDays)
        return avgIntakeCompleteDays - dailyBalance
    }

    /// Fallback Mifflin-St Jeor × activity_factor (usa la tendencia de peso actual).
    static func mifflinStJeor(weightKg: Double, heightCm: Double, age: Int,
                              sex: String, activityFactor: Double) -> Double {
        let base = 10.0 * weightKg + 6.25 * heightCm - 5.0 * Double(age)
        let bmr = sex.lowercased() == "f" ? base - 161.0 : base + 5.0
        return bmr * activityFactor
    }

    /// Elige adaptativo vs calibrating según la regla de §3.2:
    /// adaptive si ≥10 días complete y ≥10 pesajes en la ventana; si no, calibrating.
    static func tdee(completeDays: Int, weighins: Int,
                     avgIntakeCompleteDays: Double, deltaEMA: Double, windowDays: Int = 21,
                     mifflin: @autoclosure () -> Double) -> TDEEResult {
        if completeDays >= 10 && weighins >= 10 {
            return TDEEResult(kcal: tdeeAdaptive(avgIntakeCompleteDays: avgIntakeCompleteDays,
                                                 deltaEMA: deltaEMA, windowDays: windowDays),
                              status: .adaptive)
        } else {
            return TDEEResult(kcal: mifflin(), status: .calibrating)
        }
    }

    // MARK: - §5.5 Set efectivo y PR
    /// Set efectivo: is_warmup=0 AND rir ≤ 4.
    static func isEffectiveSet(rir: Int, isWarmup: Bool) -> Bool {
        !isWarmup && rir <= 4
    }

    /// PR: e1rm válido estrictamente mayor que el máximo e1rm válido histórico previo.
    static func isPR(candidateE1RM: Double?, previousBestE1RM: Double?) -> Bool {
        guard let c = candidateE1RM else { return false }
        guard let prev = previousBestE1RM else { return true }  // primer válido = PR
        return c > prev
    }

    // MARK: - §4 Schedule resolution
    /// Día del schedule que toca en `date`: schedule[(díasEntre(start, date)) % len].
    static func scheduledDayId(schedule: [String], startDate: Date, date: Date,
                               calendar: Calendar = .bogota) -> String? {
        guard !schedule.isEmpty else { return nil }
        let start = calendar.startOfDay(for: startDate)
        let target = calendar.startOfDay(for: date)
        guard let days = calendar.dateComponents([.day], from: start, to: target).day else { return nil }
        let idx = ((days % schedule.count) + schedule.count) % schedule.count
        return schedule[idx]
    }
}

extension Calendar {
    /// Calendario anclado a America/Bogota (contracts: el cliente calcula el `date`).
    static var bogota: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Bogota") ?? .current
        return c
    }
}
