import Foundation
import SwiftData
import SwiftUI

// ViewModel de PROGRESO. Fuente: GET /api/progress (+ por-ejercicio) y
// /api/energy-status; fallback local con FormulasKit (SwiftData).
@MainActor
@Observable
final class ProgressViewModel {
    var progress: Progress?
    var energy: EnergyStatus?
    var selectedExerciseId: String?
    var exerciseProgress: Progress?
    var recovery: Recovery?
    var loading = false

    // Métricas crudas por tipo (para los charts de recuperación/composición). Se cargan
    // del API (histórico amplio) con fallback a SwiftData.
    private var metricsByType: [String: [BodyMetricDTO]] = [:]

    private let env: AppEnvironment
    init(env: AppEnvironment) { self.env = env }

    func loadOverview() async {
        loading = true; defer { loading = false }
        progress = (try? await env.api.getProgress(exerciseId: nil)) ?? localOverview()
        energy = (try? await env.api.getEnergyStatus()) ?? localEnergy()
        if selectedExerciseId == nil { selectedExerciseId = defaultExercise() }
        await loadExercise()
        await loadRecovery()
    }

    // MARK: - Recuperación / composición (V2)
    private static let recoveryTypes = [
        "sleep_deep_hours", "sleep_rem_hours", "sleep_core_hours", "sleep_awake_hours",
        "sleep_hours", "sleep_midpoint_hour", "resting_hr", "hrv_ms", "body_fat_pct", "lean_mass_kg",
    ]

    func loadRecovery() async {
        recovery = try? await env.api.getRecovery(date: CBDate.day())
        let from = CBDate.day(Calendar.bogota.date(byAdding: .day, value: -400, to: Date()) ?? Date())
        let to = CBDate.day()
        for t in Self.recoveryTypes {
            if let rows = try? await env.api.getBodyMetrics(type: t, from: from, to: to), !rows.isEmpty {
                metricsByType[t] = rows
            } else {
                metricsByType[t] = localMetrics(type: t)
            }
        }
    }

    private func localMetrics(type: String) -> [BodyMetricDTO] {
        let t = type
        return ((try? env.context.fetch(FetchDescriptor<BodyMetric>(
            predicate: #Predicate { $0.typeRaw == t && $0.deleted == false }))) ?? []).map { $0.toDTO() }
    }

    private func points(_ type: String) -> [TrendPoint] {
        (metricsByType[type] ?? []).compactMap { m in
            CBDate.date(fromDay: m.date).map { TrendPoint(date: $0, value: m.value) }
        }.sorted { $0.date < $1.date }
    }

    func sleepNights() -> [SleepNight] {
        func byDate(_ t: String) -> [String: Double] {
            Dictionary((metricsByType[t] ?? []).map { ($0.date, $0.value) }, uniquingKeysWith: { _, b in b })
        }
        let deep = byDate("sleep_deep_hours"), rem = byDate("sleep_rem_hours")
        let core = byDate("sleep_core_hours"), awake = byDate("sleep_awake_hours")
        let dates = Set(deep.keys).union(rem.keys).union(core.keys)
        return dates.compactMap { d -> SleepNight? in
            guard let date = CBDate.date(fromDay: d) else { return nil }
            return SleepNight(date: date, deep: deep[d] ?? 0, rem: rem[d] ?? 0, core: core[d] ?? 0, awake: awake[d] ?? 0)
        }.sorted { $0.date < $1.date }
    }

    func rhrPoints() -> [TrendPoint] { points("resting_hr") }
    func hrvPoints() -> [TrendPoint] { points("hrv_ms") }
    func bodyFatPoints() -> [TrendPoint] { points("body_fat_pct") }
    func leanMassPoints() -> [TrendPoint] { points("lean_mass_kg") }

    var sleepNeedHours: Double { Double(env.fetchGoal(key: "sleep_need_hours")?.value ?? "") ?? FormulasKit.sleepNeedDefaultHours }

    func loadExercise() async {
        guard let id = selectedExerciseId else { return }
        exerciseProgress = (try? await env.api.getProgress(exerciseId: id)) ?? localExercise(id)
    }

    var exercisesWithHistory: [Exercise] {
        let sets = (try? env.context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.deleted == false }))) ?? []
        let ids = Set(sets.map { $0.exerciseId })
        return env.allExercises().filter { ids.contains($0.id) }
    }

    private func defaultExercise() -> String? { exercisesWithHistory.first?.id }

    // MARK: - Series para gráficos
    func e1rmPoints() -> [TrendPoint] {
        guard let series = exerciseProgress?.e1rm_series else { return [] }
        // PRs SOLO del ejercicio seleccionado (antes marcaba PRs de otros ejercicios
        // en fechas coincidentes).
        let prDates = Set((progress?.prs_recent ?? [])
            .filter { $0.exercise_id == selectedExerciseId }.map { $0.date })
        return series.compactMap { p in
            guard let d = CBDate.date(fromDay: p.date) else { return nil }
            return TrendPoint(date: d, value: p.e1rm_kg, isPR: prDates.contains(p.date))
        }
    }

    func weightTrendPoints() -> [TrendPoint] {
        (energy?.weight.trend_series ?? []).compactMap { p in
            CBDate.date(fromDay: p.date).map { TrendPoint(date: $0, value: p.ema_kg) }
        }
    }
    func rawWeightPoints() -> [TrendPoint] {
        let raw = (try? env.context.fetch(FetchDescriptor<BodyMetric>(
            predicate: #Predicate { $0.typeRaw == "weight_kg" && $0.deleted == false }))) ?? []
        return raw.compactMap { m in CBDate.date(fromTs: m.ts).map { TrendPoint(date: $0, value: m.value) } }
    }

    func volumeData(week: String?) -> [VolumeDatum] {
        let vols = progress?.weekly_volume ?? []
        let weeks = Set(vols.map { $0.week }).sorted()
        let target = week ?? weeks.last
        let filtered = vols.filter { $0.week == target }
        return filtered.map { v in
            VolumeDatum(muscle: MuscleGroup(rawValue: v.muscle_group)?.displayName ?? v.muscle_group,
                        sets: v.effective_sets, min: 10, max: 20)
        }.sorted { $0.sets > $1.sets }
    }
    func availableWeeks() -> [String] { Array(Set((progress?.weekly_volume ?? []).map { $0.week })).sorted() }

    // MARK: - Fallback local
    private func allWorkouts() -> [Workout] {
        ((try? env.context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.deleted == false }))) ?? [])
            .sorted { $0.tsStart < $1.tsStart }
    }
    private func sets(workoutId: String) -> [WorkoutSet] {
        ((try? env.context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.workoutId == workoutId && $0.deleted == false }))) ?? [])
    }

    private func localOverview() -> Progress {
        var weekly: [Progress.WeeklyVolume] = []
        var counts: [String: [String: Int]] = [:]
        var bestByExercise: [String: (Double, String)] = [:]
        for w in allWorkouts() {
            guard let d = CBDate.date(fromDay: w.date) else { continue }
            let week = isoWeek(d)
            for s in sets(workoutId: w.id) {
                if FormulasKit.isEffectiveSet(rir: s.rir, isWarmup: s.isWarmup) {
                    let mg = env.allExercises().first { $0.id == s.exerciseId }?.muscleGroupRaw ?? "chest"
                    counts[week, default: [:]][mg, default: 0] += 1
                }
                if let e = s.e1rmKg, e > (bestByExercise[s.exerciseId]?.0 ?? 0) {
                    bestByExercise[s.exerciseId] = (e, w.date)
                }
            }
        }
        for (week, muscles) in counts { for (mg, n) in muscles { weekly.append(.init(week: week, muscle_group: mg, effective_sets: n)) } }
        let prs = bestByExercise.map { (exId, v) in
            Progress.PR(exercise_id: exId, name: env.allExercises().first { $0.id == exId }?.name ?? exId, e1rm_kg: v.0, date: v.1)
        }.sorted { $0.e1rm_kg > $1.e1rm_kg }
        return Progress(weekly_volume: weekly.sorted { $0.week < $1.week }, prs_recent: prs, e1rm_series: nil, best_sets: nil)
    }

    private func localExercise(_ id: String) -> Progress {
        var series: [Progress.E1RMPoint] = []
        var best: [Progress.BestSet] = []
        for w in allWorkouts() {
            let s = sets(workoutId: w.id).filter { $0.exerciseId == id }
            let valid = s.compactMap { $0.e1rmKg }
            if let top = valid.max() { series.append(.init(date: w.date, e1rm_kg: top)) }
            if let bs = s.max(by: { ($0.e1rmKg ?? 0) < ($1.e1rmKg ?? 0) }) {
                best.append(.init(weight_kg: bs.weightKg, reps: bs.reps, rir: bs.rir, date: w.date))
            }
        }
        let overview = progress ?? localOverview()
        return Progress(weekly_volume: overview.weekly_volume, prs_recent: overview.prs_recent,
                        e1rm_series: series, best_sets: best.reversed())
    }

    private func localEnergy() -> EnergyStatus {
        let raw = (try? env.context.fetch(FetchDescriptor<BodyMetric>(
            predicate: #Predicate { $0.typeRaw == "weight_kg" && $0.deleted == false }))) ?? []
        let series = FormulasKit.emaSeries(readings: raw.compactMap { m in CBDate.date(fromTs: m.ts).map { ($0, m.value) } })
            .map { EnergyStatus.TrendPointDTO(date: CBDate.day($0.date), ema_kg: ($0.ema * 100).rounded() / 100) }
        let trend = series.last?.ema_kg
        return EnergyStatus(
            tdee: .init(kcal: 0, status: "calibrating", window_days: 21, complete_days_used: 0, weighins_used: raw.count),
            weight: .init(trend_kg: trend, trend_series: series, delta_window_kg: nil),
            intake: .init(avg_kcal_complete_days: nil, adherence_pct: nil),
            goal: .init(rate_target_kg_per_week: Double(env.fetchGoal(key: "goal_rate_kg_per_week")?.value ?? ""), rate_actual_kg_per_week: nil, on_track: nil),
            recommendation_basis: "calibrating")
    }

    private func isoWeek(_ d: Date) -> String {
        var c = Calendar(identifier: .iso8601); c.timeZone = CBDate.bogota
        let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
    }
}
