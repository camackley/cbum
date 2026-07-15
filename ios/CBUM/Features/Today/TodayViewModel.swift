import Foundation
import SwiftData
import SwiftUI

// ViewModel de HOY. Fuente: GET /api/summary/today (refrescada por sync) con
// FALLBACK a cálculo local con data SwiftData si no hay red: macros del día y
// targets son computables localmente; TDEE/tendencia muestran el último valor
// conocido con timestamp.
@MainActor
@Observable
final class TodayViewModel {
    var summary: SummaryToday?
    var recovery: Recovery?
    var isLoading = false
    var usingFallback = false
    var lastKnownAt: Date?

    private let env: AppEnvironment
    init(env: AppEnvironment) { self.env = env }

    var date: String { CBDate.day() }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            summary = try await env.api.getSummaryToday(date: date)
            usingFallback = false
            lastKnownAt = Date()
        } catch {
            // Fallback local: computa lo posible desde SwiftData.
            summary = localSummary()
            usingFallback = true
            lastKnownAt = env.config.lastSyncAt
        }
        // Recuperación (V2): full recovery para la columna DORMIR + chip; fallback local.
        recovery = (try? await env.api.getRecovery(date: date)) ?? localRecovery()
    }

    /// Estado de recuperación para el chip: full recovery, o el bloque de summary, o no_data.
    var recoveryState: String {
        recovery?.recovery_state ?? summary?.recovery?.recovery_state ?? "no_data"
    }

    func toggleDayComplete(_ complete: Bool) {
        env.setDayFlag(date: date, complete: complete)
        if summary != nil { summary?.logging_complete = complete }
    }

    // MARK: - Fallback local
    private func localSummary() -> SummaryToday {
        let ctx = env.context
        let today = date
        let meals = ((try? ctx.fetch(FetchDescriptor<Meal>(
            predicate: #Predicate { $0.date == today && $0.deleted == false }))) ?? [])
        let intake = meals.reduce(Macros.zero) { $0 + $1.macros }
        let weighed = meals.filter { $0.portionBasisRaw == "weighed" }.count
        let low = meals.filter { $0.confidence < 0.7 }.count
        let pct = meals.isEmpty ? 0 : Double(weighed) / Double(meals.count)

        let g = goalsDict()
        let targets = SummaryToday.Targets(
            kcal: dbl(g, "target_kcal"), protein_g: dbl(g, "target_protein_g"),
            carbs_g: dbl(g, "target_carbs_g"), fat_g: dbl(g, "target_fat_g"))

        // Peso: último EMA conocido de body_metrics locales.
        let weights = ((try? ctx.fetch(FetchDescriptor<BodyMetric>(
            predicate: #Predicate { $0.typeRaw == "weight_kg" && $0.deleted == false }))) ?? [])
        let series = FormulasKit.emaSeries(readings: weights.compactMap { m in CBDate.date(fromTs: m.ts).map { ($0, m.value) } })
        let trend = series.last?.ema
        let lastReading = weights.sorted { $0.ts < $1.ts }.last

        let flag = (try? ctx.fetch(FetchDescriptor<DayFlag>(predicate: #Predicate { $0.date == today })))?.first
        let session = localSession()

        return SummaryToday(
            date: today,
            intake: .init(kcal: intake.kcal, protein_g: intake.protein_g, carbs_g: intake.carbs_g, fat_g: intake.fat_g, fiber_g: intake.fiber_g),
            targets: targets,
            precision: .init(weighed_pct: pct, items: meals.count, low_confidence_items: low),
            weight: .init(trend_kg: trend.map { ($0 * 10).rounded() / 10 }, delta_7d_kg: nil,
                          last_reading_kg: lastReading?.value, last_reading_date: lastReading?.date),
            tdee: .init(kcal: 0, status: "calibrating"),
            session: session,
            logging_complete: flag?.loggingComplete ?? false)
    }

    private func localSession() -> SummaryToday.Session? {
        guard let prog = env.activeProgram()?.program,
              let start = CBDate.date(fromDay: env.activeProgram()?.startDate ?? ""),
              let target = CBDate.date(fromDay: date),
              let dayId = FormulasKit.scheduledDayId(schedule: prog.schedule, startDate: start, date: target) else { return nil }
        if dayId == "rest" { return .init(program_day_id: "rest", name: "Descanso", exercise_count: 0, completed_today: false) }
        guard let day = prog.day(id: dayId) else { return nil }
        let d = date
        let done = ((try? env.context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.date == d && $0.finished == true && $0.deleted == false }))) ?? [])
            .contains { $0.programDayId == dayId }
        return .init(program_day_id: dayId, name: day.name, exercise_count: day.exercises.count, completed_today: done)
    }

    // Fallback local de recuperación: MISMO algoritmo (RecoveryCompute) sobre SwiftData.
    private func localRecovery() -> Recovery {
        let ctx = env.context
        let today = date
        let sleepNeed = Double(goalsDict()["sleep_need_hours"] ?? "") ?? FormulasKit.sleepNeedDefaultHours
        return RecoveryCompute.build(date: today, needHours: sleepNeed) { type in
            let t = type
            let rows = ((try? ctx.fetch(FetchDescriptor<BodyMetric>(
                predicate: #Predicate { $0.typeRaw == t && $0.deleted == false }))) ?? [])
                .filter { $0.date <= today }
                .sorted { ($0.date, $0.ts) < ($1.date, $1.ts) }
            return rows.map { FormulasKit.DatedValue(date: $0.date, value: $0.value) }
        }
    }

    private func goalsDict() -> [String: String] {
        let goals = (try? env.context.fetch(FetchDescriptor<Goal>())) ?? []
        return Dictionary(uniqueKeysWithValues: goals.map { ($0.key, $0.value) })
    }
    private func dbl(_ d: [String: String], _ k: String) -> Double { Double(d[k] ?? "") ?? 0 }
}
