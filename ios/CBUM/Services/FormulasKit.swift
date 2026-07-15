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

    // MARK: - V2 §R5 Recuperación (funciones PURAS; paridad EXACTA con backend formulas.ts)
    // Baselines = mediana 28d propios (mín 14 datos). Reproducen los test vectors del delta.

    static let sleepNeedDefaultHours = 7.0
    static let baselineWindowDays = 28
    static let baselineMinN = 14

    /// Redondeo a 1 decimal (mismo `round1` del backend). `+ 0` evita -0.0.
    static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 + 0 }

    /// Mediana; nil si vacío. Par → promedio de los dos centrales.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }

    struct DatedValue { let date: String; let value: Double }   // date = YYYY-MM-DD
    struct Baseline { let value: Double; let n: Int }

    /// Mediana de los últimos 28 días CON dato, ventana terminando AYER (el valor de
    /// hoy NO contamina su propio baseline). Mínimo 14 datos; si no → nil (§R5).
    /// `endExclusive` = la fecha "hoy" que se evalúa.
    static func baseline28(_ values: [DatedValue], endExclusive: String) -> Baseline? {
        guard let start = addDays(to: endExclusive, days: -baselineWindowDays) else { return nil }
        let inWindow = values.filter { $0.date >= start && $0.date < endExclusive }
        guard inWindow.count >= baselineMinN else { return nil }
        guard let m = median(inWindow.map { $0.value }) else { return nil }
        return Baseline(value: m, n: inWindow.count)
    }

    /// deviation_pct = (hoy − baseline)/baseline × 100, redondeo 1 decimal (§R5).
    static func deviationPct(today: Double, baseline: Double) -> Double {
        guard baseline != 0 else { return 0 }
        return round1((today - baseline) / baseline * 100)
    }

    enum RhrStatus: String { case elevated, normal, noData = "no_data" }
    enum HrvStatus: String { case suppressed, normal, noData = "no_data" }
    enum SleepStatus: String { case belowNeed = "below_need", ok, noData = "no_data" }
    enum RecoveryState: String { case good, caution, low, noData = "no_data" }

    /// RHR elevated si ≥ +3% (§R5).
    static func rhrStatus(deviation: Double) -> RhrStatus { deviation >= 3 ? .elevated : .normal }
    /// HRV suppressed si ≤ −15% (§R5).
    static func hrvStatus(deviation: Double) -> HrvStatus { deviation <= -15 ? .suppressed : .normal }
    /// Sleep below_need si hours < need (default 7.0h, configurable con goal sleep_need_hours).
    static func sleepStatus(hours: Double, needHours: Double = sleepNeedDefaultHours) -> SleepStatus {
        hours < needHours ? .belowNeed : .ok
    }
    /// midpoint_drift_hours = |midpoint hoy − mediana 28d de midpoints| (§R5).
    static func midpointDrift(todayMidpoint: Double, baselineMidpoint: Double) -> Double {
        round1(abs(todayMidpoint - baselineMidpoint))
    }

    struct RecoveryStateInput {
        var sleepHours: Double?         // nil = sleep no_data
        var rhrDeviationPct: Double?    // nil = rhr no_data
        var rhrStatus: RhrStatus
        var hrvDeviationPct: Double?    // nil = hrv no_data
        var hrvStatus: HrvStatus
        var midpointDriftHours: Double?
    }

    /// recovery_state: reglas EN ORDEN, gana la primera (§R5).
    static func recoveryState(_ i: RecoveryStateInput) -> RecoveryState {
        let sleepNoData = i.sleepHours == nil
        let rhrNoData = i.rhrStatus == .noData
        let hrvNoData = i.hrvStatus == .noData

        // 1. no_data si sleep Y rhr Y hrv son no_data.
        if sleepNoData && rhrNoData && hrvNoData { return .noData }

        // 2. low si (sleep < 6.0h Y rhr elevated) O hrv ≤ −25% O rhr ≥ +7%.
        let lowBySleepRhr = (i.sleepHours.map { $0 < 6.0 } ?? false) && i.rhrStatus == .elevated
        let lowByHrv = i.hrvDeviationPct.map { $0 <= -25 } ?? false
        let lowByRhr = i.rhrDeviationPct.map { $0 >= 7 } ?? false
        if lowBySleepRhr || lowByHrv || lowByRhr { return .low }

        // 3. caution si sleep < 7.0h O rhr elevated O hrv suppressed O midpoint_drift > 1.5h.
        let cautionBySleep = i.sleepHours.map { $0 < 7.0 } ?? false
        let cautionByDrift = i.midpointDriftHours.map { $0 > 1.5 } ?? false
        if cautionBySleep || i.rhrStatus == .elevated || i.hrvStatus == .suppressed || cautionByDrift {
            return .caution
        }

        // 4. good en cualquier otro caso.
        return .good
    }

    /// Aritmética de días sobre "yyyy-MM-dd" anclada a UTC (paridad con `addDays` del
    /// backend, que no hace math de timezone). Devuelve nil si el string no parsea.
    static func addDays(to day: String, days: Int) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = day.split(separator: "-").compactMap { Int($0) }
        guard comps.count == 3 else { return nil }
        var dc = DateComponents(); dc.year = comps[0]; dc.month = comps[1]; dc.day = comps[2]
        guard let base = cal.date(from: dc), let shifted = cal.date(byAdding: .day, value: days, to: base) else { return nil }
        let out = cal.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", out.year ?? 0, out.month ?? 0, out.day ?? 0)
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
