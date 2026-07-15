import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

// HealthKitService — mapeo EXACTO de contracts §7 (spec I2).
// App → HK: comida (HKCorrelation food) y entreno (HKWorkout strength).
// HK → App → API: peso, pasos, sueño, kcal activas → body_metrics.
// La escritura ocurre tras el save LOCAL (no tras el sync). Metadata cbum_id
// evita duplicar al re-escribir; borrar/editar → borrar sample por cbum_id.
@MainActor
final class HealthKitService {
    static let metadataKey = "cbum_id"

    #if canImport(HealthKit)
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // Tipos de escritura (nutrición + workout) y lectura (peso/pasos/sueño/kcal).
    private var writeTypes: Set<HKSampleType> {
        var s: Set<HKSampleType> = [HKWorkoutType.workoutType()]
        [HKQuantityTypeIdentifier.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates,
         .dietaryFatTotal, .dietaryFiber].forEach { if let t = HKQuantityType.quantityType(forIdentifier: $0) { s.insert(t) } }
        return s
    }
    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = []
        // V1 + V2 vitales/composición (delta §R1).
        [HKQuantityTypeIdentifier.bodyMass, .stepCount, .activeEnergyBurned,
         .heartRateVariabilitySDNN, .restingHeartRate, .respiratoryRate,
         .bodyFatPercentage, .leanBodyMass].forEach {
            if let t = HKQuantityType.quantityType(forIdentifier: $0) { s.insert(t) } }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        return s
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do { try await store.requestAuthorization(toShare: writeTypes, read: readTypes); return true }
        catch { return false }
    }

    // MARK: - App → HK: comida
    func writeMeal(id: String, tsISO: String, macros: Macros) async {
        guard isAvailable, let ts = CBDate.date(fromTs: tsISO) else { return }
        await deleteSamples(cbumId: id)   // idempotente (edición/re-escritura)
        var samples: [HKSample] = []
        func add(_ idf: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double?) {
            guard let value, value > 0, let type = HKQuantityType.quantityType(forIdentifier: idf) else { return }
            let q = HKQuantity(unit: unit, doubleValue: value)
            samples.append(HKQuantitySample(type: type, quantity: q, start: ts, end: ts,
                                            metadata: [Self.metadataKey: id]))
        }
        add(.dietaryEnergyConsumed, .kilocalorie(), macros.kcal)
        add(.dietaryProtein, .gram(), macros.protein_g)
        add(.dietaryCarbohydrates, .gram(), macros.carbs_g)
        add(.dietaryFatTotal, .gram(), macros.fat_g)
        add(.dietaryFiber, .gram(), macros.fiber_g)
        guard !samples.isEmpty else { return }
        let correlationType = HKCorrelationType.correlationType(forIdentifier: .food)!
        let food = HKCorrelation(type: correlationType, start: ts, end: ts,
                                 objects: Set(samples), metadata: [Self.metadataKey: id])
        try? await store.save(food)
    }

    // MARK: - App → HK: entreno
    func writeWorkout(id: String, startISO: String, endISO: String) async {
        guard isAvailable, let start = CBDate.date(fromTs: startISO), let end = CBDate.date(fromTs: endISO) else { return }
        await deleteSamples(cbumId: id)
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([Self.metadataKey: id])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch { /* best-effort */ }
    }

    // MARK: - Borrado por cbum_id (comida o entreno editado/borrado)
    func deleteSamples(cbumId: String) async {
        guard isAvailable else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.metadataKey, allowedValues: [cbumId])
        let types: [HKSampleType] = Array(writeTypes) + [HKCorrelationType.correlationType(forIdentifier: .food)!]
        for type in types {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] _, samples, _ in
                    if let samples, !samples.isEmpty { self?.store.delete(samples) { _, _ in cont.resume() } }
                    else { cont.resume() }
                }
                store.execute(q)
            }
        }
    }

    // MARK: - HK → App: lecturas (devuelven BodyMetricDTO para encolar)
    /// bodyMass: cada sample como weight_kg (source healthkit). Anchor persistido.
    func readWeight() async -> [BodyMetricDTO] {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        return await withCheckedContinuation { cont in
            let anchor = loadAnchor(key: "hk.anchor.bodyMass")
            let q = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, newAnchor, _ in
                self?.saveAnchor(newAnchor, key: "hk.anchor.bodyMass")
                let dtos = (samples as? [HKQuantitySample])?.map { s -> BodyMetricDTO in
                    let kg = s.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    return BodyMetricDTO(id: UUID().uuidString, ts: CBDate.ts(s.startDate), date: CBDate.day(s.startDate),
                                         type: "weight_kg", value: (kg * 10).rounded() / 10, source: "healthkit")
                } ?? []
                cont.resume(returning: dtos)
            }
            store.execute(q)
        }
    }

    /// stepCount / activeEnergyBurned: total por día (1 valor/día, ts = fin de día Bogotá).
    func readDailyTotals(days: Int = 7) async -> [BodyMetricDTO] {
        var out: [BodyMetricDTO] = []
        out += await dailyStat(.stepCount, unit: .count(), type: "steps", days: days)
        out += await dailyStat(.activeEnergyBurned, unit: .kilocalorie(), type: "active_kcal", days: days)
        return out
    }

    private func dailyStat(_ idf: HKQuantityTypeIdentifier, unit: HKUnit, type: String, days: Int) async -> [BodyMetricDTO] {
        guard isAvailable, let qType = HKQuantityType.quantityType(forIdentifier: idf) else { return [] }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = CBDate.bogota
        let end = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [] }
        let interval = DateComponents(day: 1)
        let anchorDate = cal.startOfDay(for: start)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: qType, quantitySamplePredicate: nil,
                                                options: .cumulativeSum, anchorDate: anchorDate, intervalComponents: interval)
            q.initialResultsHandler = { _, results, _ in
                var dtos: [BodyMetricDTO] = []
                results?.enumerateStatistics(from: start, to: Date()) { stat, _ in
                    guard let sum = stat.sumQuantity() else { return }
                    let v = sum.doubleValue(for: unit)
                    guard v > 0 else { return }
                    let endOfDay = cal.date(byAdding: DateComponents(day: 1, second: -1), to: stat.startDate) ?? stat.startDate
                    dtos.append(BodyMetricDTO(id: UUID().uuidString, ts: CBDate.ts(endOfDay), date: CBDate.day(stat.startDate),
                                             type: type, value: (v).rounded(), source: "healthkit"))
                }
                cont.resume(returning: dtos)
            }
            store.execute(q)
        }
    }

    /// sleepAnalysis con FASES (delta §R1). Ventana nocturna 18:00→18:00 (Bogotá),
    /// asignada a la fecha de despertar; produce sleep_hours (Σ asleep*), deep/rem/core
    /// (unspecified suma a core y a total), awake, inbed y midpoint decimal local del
    /// bloque principal. Si iPhone y wearable reportan la misma noche, se prefiere la
    /// fuente CON fases (deep/rem/core) — evita doble conteo (ver DECISIONS).
    func readSleepPhases(days: Int = 14) async -> [BodyMetricDTO] {
        guard isAvailable, let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = CBDate.bogota
        let end = Date()
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let cats = (samples as? [HKCategorySample]) ?? []
                // Agrupar por (fecha de despertar, fuente). wakeDate = día de (start + 6h)
                // → ventana [D-1 18:00, D 18:00) mapea a la fecha D.
                var byNight: [String: [String: [HKCategorySample]]] = [:]
                for s in cats {
                    let wakeDay = CBDate.day(s.startDate.addingTimeInterval(6 * 3600))
                    let src = s.sourceRevision.source.bundleIdentifier
                    byNight[wakeDay, default: [:]][src, default: []].append(s)
                }
                var out: [BodyMetricDTO] = []
                for (day, bySource) in byNight {
                    guard let chosen = Self.preferredSleepSource(bySource) else { continue }
                    out += Self.sleepDTOs(day: day, samples: chosen)
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    // Elige la fuente preferida de una noche: la que tenga fases (deep/rem/core);
    // si ninguna las tiene o hay empate, la de mayor tiempo asleep.
    nonisolated private static func preferredSleepSource(_ bySource: [String: [HKCategorySample]]) -> [HKCategorySample]? {
        func asleepSecs(_ ss: [HKCategorySample]) -> Double {
            ss.filter { asleepValues.contains($0.value) }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        }
        func hasPhases(_ ss: [HKCategorySample]) -> Bool {
            ss.contains { phaseValues.contains($0.value) }
        }
        let withPhases = bySource.values.filter { hasPhases($0) }
        let pool = withPhases.isEmpty ? Array(bySource.values) : withPhases
        return pool.max { asleepSecs($0) < asleepSecs($1) }
    }

    nonisolated private static let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
    ]
    nonisolated private static let phaseValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
    ]

    nonisolated private static func sleepDTOs(day: String, samples: [HKCategorySample]) -> [BodyMetricDTO] {
        func hours(_ vals: Set<Int>) -> Double {
            samples.filter { vals.contains($0.value) }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 3600
        }
        let deep = hours([HKCategoryValueSleepAnalysis.asleepDeep.rawValue])
        let rem = hours([HKCategoryValueSleepAnalysis.asleepREM.rawValue])
        // unspecified suma a core y al total (delta §R1).
        let core = hours([HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                          HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue])
        let awake = hours([HKCategoryValueSleepAnalysis.awake.rawValue])
        let inbed = hours([HKCategoryValueSleepAnalysis.inBed.rawValue])
        let total = deep + rem + core
        guard total > 0 else { return [] }

        // midpoint del bloque principal: entre el 1er inicio y el último fin de asleep*.
        let asleep = samples.filter { asleepValues.contains($0.value) }
        var midpoint: Double? = nil
        if let first = asleep.map(\.startDate).min(), let last = asleep.map(\.endDate).max() {
            let mid = first.addingTimeInterval(last.timeIntervalSince(first) / 2)
            midpoint = round2(decimalHour(mid))
        }

        let ts = CBDate.ts(CBDate.date(fromDay: day) ?? Date())
        func dto(_ type: String, _ value: Double) -> BodyMetricDTO {
            BodyMetricDTO(id: UUID().uuidString, ts: ts, date: day, type: type, value: round2(value), source: "healthkit")
        }
        var out = [dto("sleep_hours", total), dto("sleep_deep_hours", deep), dto("sleep_rem_hours", rem),
                   dto("sleep_core_hours", core)]
        if awake > 0 { out.append(dto("sleep_awake_hours", awake)) }
        if inbed > 0 { out.append(dto("sleep_inbed_hours", inbed)) }
        if let m = midpoint { out.append(BodyMetricDTO(id: UUID().uuidString, ts: ts, date: day, type: "sleep_midpoint_hour", value: m, source: "healthkit")) }
        return out
    }

    nonisolated private static func decimalHour(_ date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = CBDate.bogota
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }
    nonisolated private static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

    /// Vitales diarios (delta §R1): HRV (promedio SDNN del día, ms), resting_hr y
    /// respiratory_rate (1 valor/día). Promedio discreto por día en la ventana.
    func readDailyVitals(days: Int = 14, hrv: Bool = true, rhr: Bool = true, resp: Bool = true) async -> [BodyMetricDTO] {
        var out: [BodyMetricDTO] = []
        if hrv { out += await dailyDiscreteAvg(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), type: "hrv_ms", days: days, decimals: 1) }
        if rhr { out += await dailyDiscreteAvg(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), type: "resting_hr", days: days, decimals: 0) }
        if resp { out += await dailyDiscreteAvg(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), type: "respiratory_rate", days: days, decimals: 1) }
        return out
    }

    private func dailyDiscreteAvg(_ idf: HKQuantityTypeIdentifier, unit: HKUnit, type: String, days: Int, decimals: Int) async -> [BodyMetricDTO] {
        guard isAvailable, let qType = HKQuantityType.quantityType(forIdentifier: idf) else { return [] }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = CBDate.bogota
        let end = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [] }
        let anchorDate = cal.startOfDay(for: start)
        let m = pow(10.0, Double(decimals))
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: qType, quantitySamplePredicate: nil,
                                                options: .discreteAverage, anchorDate: anchorDate, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, _ in
                var dtos: [BodyMetricDTO] = []
                results?.enumerateStatistics(from: start, to: Date()) { stat, _ in
                    guard let avg = stat.averageQuantity() else { return }
                    let v = avg.doubleValue(for: unit)
                    guard v > 0 else { return }
                    let day = CBDate.day(stat.startDate)
                    let endOfDay = cal.date(byAdding: DateComponents(day: 1, second: -1), to: stat.startDate) ?? stat.startDate
                    dtos.append(BodyMetricDTO(id: UUID().uuidString, ts: CBDate.ts(endOfDay), date: day,
                                             type: type, value: (v * m).rounded() / m, source: "healthkit"))
                }
                cont.resume(returning: dtos)
            }
            store.execute(q)
        }
    }

    /// Composición (báscula): body_fat_pct (0–100) y lean_mass_kg, cada muestra
    /// (dedup por UNIQUE del server). Anchors persistidos por tipo, como el peso.
    func readBodyComposition() async -> [BodyMetricDTO] {
        var out: [BodyMetricDTO] = []
        out += await anchoredSamples(.bodyFatPercentage, unit: .percent(), type: "body_fat_pct",
                                     anchorKey: "hk.anchor.bodyFat", transform: { $0 * 100 }, decimals: 1)
        out += await anchoredSamples(.leanBodyMass, unit: .gramUnit(with: .kilo), type: "lean_mass_kg",
                                     anchorKey: "hk.anchor.leanMass", transform: { $0 }, decimals: 1)
        return out
    }

    private func anchoredSamples(_ idf: HKQuantityTypeIdentifier, unit: HKUnit, type: String,
                                 anchorKey: String, transform: @escaping (Double) -> Double, decimals: Int) async -> [BodyMetricDTO] {
        guard isAvailable, let qType = HKQuantityType.quantityType(forIdentifier: idf) else { return [] }
        let m = pow(10.0, Double(decimals))
        return await withCheckedContinuation { cont in
            let anchor = loadAnchor(key: anchorKey)
            let q = HKAnchoredObjectQuery(type: qType, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, newAnchor, _ in
                self?.saveAnchor(newAnchor, key: anchorKey)
                let dtos = (samples as? [HKQuantitySample])?.map { s -> BodyMetricDTO in
                    let v = transform(s.quantity.doubleValue(for: unit))
                    return BodyMetricDTO(id: UUID().uuidString, ts: CBDate.ts(s.startDate), date: CBDate.day(s.startDate),
                                         type: type, value: (v * m).rounded() / m, source: "healthkit")
                } ?? []
                cont.resume(returning: dtos)
            }
            store.execute(q)
        }
    }

    // MARK: - Anchor persistence (nonisolated: se llaman desde handlers de HK)
    nonisolated private func loadAnchor(key: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
    nonisolated private func saveAnchor(_ anchor: HKQueryAnchor?, key: String) {
        guard let anchor, let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Estado de autorización de escritura (para Ajustes).
    func writeAuthorized() -> Bool {
        guard isAvailable, let t = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return false }
        return store.authorizationStatus(for: t) == .sharingAuthorized
    }

    #else
    var isAvailable: Bool { false }
    func requestAuthorization() async -> Bool { false }
    func writeMeal(id: String, tsISO: String, macros: Macros) async {}
    func writeWorkout(id: String, startISO: String, endISO: String) async {}
    func deleteSamples(cbumId: String) async {}
    func readWeight() async -> [BodyMetricDTO] { [] }
    func readDailyTotals(days: Int = 7) async -> [BodyMetricDTO] { [] }
    func readSleepPhases(days: Int = 14) async -> [BodyMetricDTO] { [] }
    func readDailyVitals(days: Int = 14, hrv: Bool = true, rhr: Bool = true, resp: Bool = true) async -> [BodyMetricDTO] { [] }
    func readBodyComposition() async -> [BodyMetricDTO] { [] }
    func writeAuthorized() -> Bool { false }
    #endif
}
