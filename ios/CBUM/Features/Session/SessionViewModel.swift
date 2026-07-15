import Foundation
import SwiftData
import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif

// Fila de set en la UI: draft (no guardado) o guardado (persistido en SwiftData).
struct SetRow: Identifiable {
    var id: String
    var setNumber: Int
    var weight: Double
    var reps: Int
    var rir: Int?
    var isWarmup: Bool
    var saved: Bool
    var e1rm: Double?
    var isPR: Bool
}

// Ejercicio de la sesión (prescripción + sugerencia + filas de sets).
struct SessionExercise: Identifiable {
    var id: String { exerciseId }
    var exerciseId: String
    var name: String
    var prescribedSets: Int
    var repRange: [Int]
    var targetRir: Int
    var restSec: Int
    var incrementKg: Double
    var suggestedKg: Double?
    var suggestionReason: String
    var lastSessionLabel: String?
    var rows: [SetRow]

    var repMax: Int { repRange.last ?? 8 }
    var completedSets: Int { rows.filter { $0.saved && !$0.isWarmup }.count }
}

// Máquina de estados: idle → active → summary (spec I3).
@MainActor
@Observable
final class SessionViewModel {
    enum Phase { case idle, active, summary }

    var phase: Phase = .idle
    var dayName: String = ""
    var programDayId: String?
    var exercises: [SessionExercise] = []
    var activeExerciseIndex: Int = 0
    var isRest: Bool = false          // día de descanso
    var loadError: String?
    var prToast: PRToastData?

    // Rest timer
    var restRemaining: Int? = nil
    var restDuration: Int = 0
    var restExerciseName: String = ""
    private var restTask: Task<Void, Never>?

    // Workout activo
    private var workout: Workout?
    var elapsedLabel: String = "00:00:00"
    private var tickTask: Task<Void, Never>?

    private let env: AppEnvironment
    init(env: AppEnvironment) { self.env = env }

    var hasActiveSession: Bool { phase == .active }

    // MARK: - Resume (kill de la app no pierde nada)
    func resumeIfNeeded() {
        guard workout == nil else { return }
        let today = CBDate.day()
        if let existing = ((try? env.context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.date == today && $0.finished == false && $0.deleted == false }))) ?? []).first {
            workout = existing
            resumeSession()   // reconstruye desde los sets persistidos (offline, libre o programado)
        }
    }

    /// Reconstruye la sesión desde los WorkoutSet ya guardados del workout activo
    /// (no desde el día del programa): así funciona para entreno libre, si hoy es
    /// "rest", si el programa cambió, y sin red. Aceptación I3 #2 (sesión intacta).
    private func resumeSession() {
        guard let w = workout else { return }
        let wid = w.id   // #Predicate no soporta keypaths de objetos capturados (w.id)
        let sets = ((try? env.context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.workoutId == wid && $0.deleted == false }))) ?? [])
            .sorted { $0.setNumber < $1.setNumber }
        let prog = env.activeProgram()?.program
        let progDay = w.programDayId.flatMap { id in prog?.day(id: id) }
        programDayId = w.programDayId
        dayName = progDay?.name ?? (w.programDayId == nil ? "Entreno libre" : "Entreno")
        isRest = false

        // Orden de ejercicios por primera aparición.
        var order: [String] = []
        var byExercise: [String: [WorkoutSet]] = [:]
        for s in sets {
            if byExercise[s.exerciseId] == nil { order.append(s.exerciseId) }
            byExercise[s.exerciseId, default: []].append(s)
        }
        exercises = order.map { exId in
            let pe = progDay?.exercises.first { $0.exercise_id == exId }
            let cat = env.allExercises().first { $0.id == exId }
            var se = SessionExercise(
                exerciseId: exId, name: cat?.name ?? exId,
                prescribedSets: pe?.sets ?? 3, repRange: pe?.rep_range ?? [6, 10],
                targetRir: pe?.target_rir ?? 2, restSec: pe?.rest_sec ?? 150,
                incrementKg: cat?.incrementKg ?? 2.5,
                suggestedKg: byExercise[exId]?.last?.weightKg, suggestionReason: "repeat_weight",
                lastSessionLabel: nil, rows: [])
            var rows = (byExercise[exId] ?? []).map { s in
                SetRow(id: s.id, setNumber: s.setNumber, weight: s.weightKg, reps: s.reps, rir: s.rir,
                       isWarmup: s.isWarmup, saved: true, e1rm: s.e1rmKg, isPR: false)
            }
            let workDone = rows.filter { !$0.isWarmup }.count
            if workDone < se.prescribedSets {
                let nextNum = (rows.map(\.setNumber).max() ?? 0) + 1
                rows.append(draftRow(number: nextNum, weight: rows.last?.weight ?? se.suggestedKg ?? 0, repMax: se.repMax))
            }
            se.rows = rows
            return se
        }
        phase = .active
        startTick()
    }

    // MARK: - Inicio
    func start(free: Bool) async {
        if free {
            await startFreeWorkout()
        } else {
            await loadSession()
        }
    }

    private func startFreeWorkout() async {
        let w = Workout(tsStart: CBDate.ts(), date: CBDate.day(), programDayId: nil)
        env.context.insert(w); try? env.context.save()
        workout = w
        dayName = "Entreno libre"
        programDayId = nil
        exercises = []
        isRest = false
        phase = .active
        startTick()
    }

    private func loadSession() async {
        do {
            let next = try await env.api.getNextSession(date: CBDate.day())
            if next.program_day_id == "rest" { isRest = true; phase = .idle; return }
            dayName = next.name
            programDayId = next.program_day_id
            if workout == nil {
                let w = Workout(tsStart: CBDate.ts(), date: CBDate.day(), programDayId: next.program_day_id)
                env.context.insert(w); try? env.context.save()
                workout = w
            }
            exercises = next.exercises.map { buildExercise(from: $0) }
            phase = .active
            startTick()
        } catch {
            // Offline: intentar reconstruir del programa local + historial (fallback).
            if let local = buildLocalSession() {
                dayName = local.0; programDayId = local.1; exercises = local.2
                if workout == nil {
                    let w = Workout(tsStart: CBDate.ts(), date: CBDate.day(), programDayId: local.1)
                    env.context.insert(w); try? env.context.save(); workout = w
                }
                phase = .active
                startTick()
            } else {
                loadError = "No se pudo cargar la sesión (sin red ni caché)."
            }
        }
    }

    private func buildExercise(from e: NextSession.Exercise) -> SessionExercise {
        let inc = env.allExercises().first { $0.id == e.exercise_id }?.incrementKg ?? 2.5
        let last = e.last_session.map { "\($0.date) · \(fmt($0.top_set.weight_kg))kg×\($0.top_set.reps)@\($0.top_set.rir)" }
        var se = SessionExercise(
            exerciseId: e.exercise_id, name: e.name, prescribedSets: e.sets, repRange: e.rep_range,
            targetRir: e.target_rir, restSec: e.rest_sec, incrementKg: inc,
            suggestedKg: e.suggested_weight_kg, suggestionReason: e.suggestion_reason,
            lastSessionLabel: last, rows: [])
        se.rows = existingRows(for: se)
        if se.rows.isEmpty { se.rows = [draftRow(number: 1, weight: e.suggested_weight_kg ?? 0, repMax: e.rep_range.last ?? 8)] }
        return se
    }

    // Reconstruye filas ya guardadas (resume) desde SwiftData.
    private func existingRows(for se: SessionExercise) -> [SetRow] {
        guard let wid = workout?.id else { return [] }
        let exId = se.exerciseId
        let saved = ((try? env.context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.workoutId == wid && $0.exerciseId == exId && $0.deleted == false }))) ?? [])
            .sorted { $0.setNumber < $1.setNumber }
        var rows = saved.map { s in
            SetRow(id: s.id, setNumber: s.setNumber, weight: s.weightKg, reps: s.reps, rir: s.rir,
                   isWarmup: s.isWarmup, saved: true, e1rm: s.e1rmKg, isPR: false)
        }
        // fila draft para el siguiente set
        let nextNum = (rows.map(\.setNumber).max() ?? 0) + 1
        if rows.count < se.prescribedSets {
            let w = rows.last?.weight ?? se.suggestedKg ?? 0
            rows.append(draftRow(number: nextNum, weight: w, repMax: se.repMax))
        }
        return rows
    }

    private func draftRow(number: Int, weight: Double, repMax: Int) -> SetRow {
        SetRow(id: UUID().uuidString, setNumber: number, weight: weight, reps: repMax,
               rir: nil, isWarmup: false, saved: false, e1rm: nil, isPR: false)
    }

    // MARK: - Guardar set
    func saveSet(exerciseIndex: Int, rowId: String) {
        guard exercises.indices.contains(exerciseIndex),
              let rowIdx = exercises[exerciseIndex].rows.firstIndex(where: { $0.id == rowId }),
              let rir = exercises[exerciseIndex].rows[rowIdx].rir,
              let wid = workout?.id else { return }
        var row = exercises[exerciseIndex].rows[rowIdx]
        let ex = exercises[exerciseIndex]

        // Persistir WorkoutSet (outbox al finalizar; e1rm local con misma fórmula §5.3)
        let set = WorkoutSet(id: row.id, workoutId: wid, exerciseId: ex.exerciseId, setNumber: row.setNumber,
                             weightKg: row.weight, reps: row.reps, rir: rir, isWarmup: row.isWarmup)
        env.saveSet(set)   // calcula e1rm
        row.e1rm = set.e1rmKg
        row.saved = true

        // Detección de PR contra máximo histórico local (excluyendo este set)
        if let e1 = set.e1rmKg {
            let prev = maxHistoricalE1RM(exerciseId: ex.exerciseId, excludingSetId: set.id)
            if FormulasKit.isPR(candidateE1RM: e1, previousBestE1RM: prev) {
                row.isPR = true
                Haptics.success()
                prToast = PRToastData(exercise: ex.name,
                                      detail: "e1RM \(fmt(e1)) kg" + (prev.map { " · +\(fmt(e1 - $0)) vs anterior" } ?? ""))
            } else {
                Haptics.tap()
            }
        } else {
            Haptics.tap()
        }
        exercises[exerciseIndex].rows[rowIdx] = row

        // Arrancar rest timer con rest_sec del programa
        if !row.isWarmup { startRest(seconds: ex.restSec, exerciseName: ex.name) }

        // Añadir draft del siguiente set si faltan
        appendNextDraftIfNeeded(exerciseIndex: exerciseIndex)
    }

    private func appendNextDraftIfNeeded(exerciseIndex: Int) {
        var ex = exercises[exerciseIndex]
        let savedWork = ex.rows.filter { $0.saved && !$0.isWarmup }.count
        let hasDraft = ex.rows.contains { !$0.saved }
        if savedWork < ex.prescribedSets && !hasDraft {
            let nextNum = (ex.rows.map(\.setNumber).max() ?? 0) + 1
            let w = ex.rows.last(where: { $0.saved })?.weight ?? ex.suggestedKg ?? 0
            ex.rows.append(draftRow(number: nextNum, weight: w, repMax: ex.repMax))
            exercises[exerciseIndex] = ex
        }
    }

    func addExtraSet(exerciseIndex: Int) {
        var ex = exercises[exerciseIndex]
        let nextNum = (ex.rows.map(\.setNumber).max() ?? 0) + 1
        let w = ex.rows.last?.weight ?? ex.suggestedKg ?? 0
        ex.rows.append(draftRow(number: nextNum, weight: w, repMax: ex.repMax))
        exercises[exerciseIndex] = ex
    }

    func toggleWarmup(exerciseIndex: Int, rowId: String) {
        guard let i = exercises[exerciseIndex].rows.firstIndex(where: { $0.id == rowId }) else { return }
        exercises[exerciseIndex].rows[i].isWarmup.toggle()
    }

    private func maxHistoricalE1RM(exerciseId: String, excludingSetId: String) -> Double? {
        let sets = ((try? env.context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId && $0.deleted == false && $0.id != excludingSetId }))) ?? [])
        // Excluir sets de workouts borrados (una sesión descartada no cuenta para PR).
        let liveWorkoutIds = Set(((try? env.context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.deleted == false }))) ?? []).map { $0.id })
        return sets.filter { liveWorkoutIds.contains($0.workoutId) }.compactMap { $0.e1rmKg }.max()
    }

    // MARK: - Sustituir ejercicio (mismo pattern → mismo muscle_group)
    func substitutionOptions(for exerciseIndex: Int) -> [Exercise] {
        guard exercises.indices.contains(exerciseIndex) else { return [] }
        let currentId = exercises[exerciseIndex].exerciseId
        let catalog = env.allExercises().filter { $0.id != currentId }
        guard let current = env.allExercises().first(where: { $0.id == currentId }) else { return catalog }
        let samePattern = catalog.filter { $0.pattern == current.pattern }
        let sameMuscle = catalog.filter { $0.pattern != current.pattern && $0.muscleGroup == current.muscleGroup }
        return samePattern + sameMuscle
    }

    func substitute(exerciseIndex: Int, with newExercise: Exercise) {
        var ex = exercises[exerciseIndex]
        // Mantener prescripción; recalcular sugerencia del historial del nuevo ejercicio (§5.4)
        let hist = lastSessionSets(exerciseId: newExercise.id)
        let sug = FormulasKit.suggestWeight(
            lastSessionSets: hist.map { FormulasKit.WorkingSet(weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, isWarmup: $0.isWarmup) },
            prescribedSets: ex.prescribedSets, repRangeMax: ex.repMax, targetRIR: ex.targetRir, incrementKg: newExercise.incrementKg)
        ex.exerciseId = newExercise.id
        ex.name = newExercise.name
        ex.incrementKg = newExercise.incrementKg
        ex.suggestedKg = sug.weightKg
        ex.suggestionReason = sug.reason.rawValue
        ex.lastSessionLabel = hist.last.map { "\(fmt($0.weightKg))kg×\($0.reps)@\($0.rir)" }
        ex.rows = [draftRow(number: 1, weight: sug.weightKg ?? 0, repMax: ex.repMax)]
        exercises[exerciseIndex] = ex
    }

    private func lastSessionSets(exerciseId: String) -> [WorkoutSet] {
        let all = ((try? env.context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId && $0.deleted == false && $0.isWarmup == false }))) ?? [])
        // agrupar por workout, tomar el más reciente
        let byWorkout = Dictionary(grouping: all, by: { $0.workoutId })
        let workoutsById = ((try? env.context.fetch(FetchDescriptor<Workout>())) ?? [])
        let sorted = byWorkout.compactMap { (wid, sets) -> (String, [WorkoutSet])? in
            // Excluir el workout en curso y los borrados (descartados no son "última sesión").
            guard let w = workoutsById.first(where: { $0.id == wid }),
                  w.id != workout?.id, !w.deleted else { return nil }
            return (w.tsStart, sets)
        }.sorted { $0.0 < $1.0 }
        return sorted.last?.1.sorted { $0.setNumber < $1.setNumber } ?? []
    }

    // MARK: - Add exercise (entreno libre)
    func addExercise(_ e: Exercise) {
        let hist = lastSessionSets(exerciseId: e.id)
        let repRange = [6, 10]
        let freeSets = 3
        let sug = FormulasKit.suggestWeight(
            lastSessionSets: hist.map { FormulasKit.WorkingSet(weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, isWarmup: $0.isWarmup) },
            prescribedSets: freeSets, repRangeMax: repRange.last!, targetRIR: 2, incrementKg: e.incrementKg)
        var se = SessionExercise(exerciseId: e.id, name: e.name, prescribedSets: 3, repRange: repRange,
                                 targetRir: 2, restSec: 150, incrementKg: e.incrementKg,
                                 suggestedKg: sug.weightKg, suggestionReason: sug.reason.rawValue,
                                 lastSessionLabel: nil, rows: [])
        se.rows = [draftRow(number: 1, weight: sug.weightKg ?? 0, repMax: se.repMax)]
        exercises.append(se)
        activeExerciseIndex = exercises.count - 1
    }

    // MARK: - Rest timer
    func startRest(seconds: Int, exerciseName: String) {
        restTask?.cancel()
        restDuration = seconds
        restRemaining = seconds
        restExerciseName = exerciseName
        scheduleRestNotification(after: seconds)
        restTask = Task { [weak self] in
            while let r = self?.restRemaining, r > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    if let rr = self.restRemaining, rr > 0 { self.restRemaining = rr - 1 }
                    if self.restRemaining == 0 { Haptics.timerDone() }
                }
            }
        }
    }
    func addThirtyToRest() { if let r = restRemaining { restRemaining = r + 30 } }
    func skipRest() { restTask?.cancel(); restRemaining = nil; cancelRestNotification() }

    private func scheduleRestNotification(after seconds: Int) {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        // Pedir permiso UNA sola vez (no en cada set).
        if !UserDefaults.standard.bool(forKey: "cbum.notifAuthAsked") {
            UserDefaults.standard.set(true, forKey: "cbum.notifAuthAsked")
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = "Descanso terminado"
        content.body = "Siguiente set: \(restExerciseName)"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        center.add(UNNotificationRequest(identifier: "rest-timer", content: content, trigger: trigger))
        #endif
    }
    private func cancelRestNotification() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest-timer"])
        #endif
    }

    // MARK: - Cronómetro de sesión
    private func startTick() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.updateElapsed() }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
    private func updateElapsed() {
        guard let start = workout.flatMap({ CBDate.date(fromTs: $0.tsStart) }) else { return }
        let secs = Int(Date().timeIntervalSince(start))
        elapsedLabel = String(format: "%02d:%02d:%02d", secs / 3600, (secs % 3600) / 60, secs % 60)
    }

    // MARK: - Finalizar
    func finish() {
        guard let w = workout else { return }
        skipRest()
        tickTask?.cancel()
        env.finishWorkout(w)   // ts_end, POST outbox, HKWorkout
        phase = .summary
    }

    func discard() {
        skipRest(); tickTask?.cancel()
        if let w = workout { env.discardWorkout(w) }   // borra sets, limpia outbox, DELETE si aplica
        reset()
    }

    func reset() {
        workout = nil; exercises = []; phase = .idle; activeExerciseIndex = 0; isRest = false; prToast = nil
    }

    // MARK: - Resumen
    func summaryData() -> SessionSummaryData {
        let allSaved = exercises.flatMap { ex in ex.rows.filter { $0.saved } }
        let workSets = exercises.flatMap { ex in ex.rows.filter { $0.saved && !$0.isWarmup } }
        let totalVolume = workSets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        let prs = exercises.flatMap { ex in ex.rows.filter { $0.isPR }.map { (ex.name, $0.e1rm ?? 0) } }
        var byMuscle: [String: Int] = [:]
        for ex in exercises {
            let mg = env.allExercises().first { $0.id == ex.exerciseId }?.muscleGroup.displayName ?? "—"
            let eff = ex.rows.filter { $0.saved && FormulasKit.isEffectiveSet(rir: $0.rir ?? 5, isWarmup: $0.isWarmup) }.count
            if eff > 0 { byMuscle[mg, default: 0] += eff }
        }
        let perExercise = exercises.map { ex -> SessionSummaryData.ExerciseLine in
            let top = ex.rows.filter { $0.saved && !$0.isWarmup }.max { ($0.e1rm ?? 0) < ($1.e1rm ?? 0) }
            return .init(name: ex.name, sets: ex.rows.filter { $0.saved && !$0.isWarmup }.count,
                         topSet: top.map { "\(fmt($0.weight))kg×\($0.reps)" } ?? "—",
                         isPR: ex.rows.contains { $0.isPR })
        }
        return SessionSummaryData(
            duration: elapsedLabel, totalSets: allSaved.count, volumeKg: totalVolume,
            prs: prs, byMuscle: byMuscle, exercises: perExercise)
    }

    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    // MARK: - Fallback offline session (programa local + §5.4)
    private func buildLocalSession() -> (String, String, [SessionExercise])? {
        guard let prog = env.activeProgram()?.program,
              let start = CBDate.date(fromDay: env.activeProgram()?.startDate ?? ""),
              let target = CBDate.date(fromDay: CBDate.day()),
              let dayId = FormulasKit.scheduledDayId(schedule: prog.schedule, startDate: start, date: target),
              dayId != "rest", let day = prog.day(id: dayId) else { return nil }
        let exs = day.exercises.map { pe -> SessionExercise in
            let hist = lastSessionSets(exerciseId: pe.exercise_id)
            let inc = env.allExercises().first { $0.id == pe.exercise_id }?.incrementKg ?? 2.5
            let sug = FormulasKit.suggestWeight(
                lastSessionSets: hist.map { FormulasKit.WorkingSet(weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, isWarmup: $0.isWarmup) },
                prescribedSets: pe.sets, repRangeMax: pe.rep_range.last ?? 8, targetRIR: pe.target_rir, incrementKg: inc)
            let name = env.allExercises().first { $0.id == pe.exercise_id }?.name ?? pe.exercise_id
            var se = SessionExercise(exerciseId: pe.exercise_id, name: name, prescribedSets: pe.sets,
                                     repRange: pe.rep_range, targetRir: pe.target_rir, restSec: pe.rest_sec,
                                     incrementKg: inc, suggestedKg: sug.weightKg, suggestionReason: sug.reason.rawValue,
                                     lastSessionLabel: hist.last.map { "\(fmt($0.weightKg))kg×\($0.reps)@\($0.rir)" }, rows: [])
            se.rows = [draftRow(number: 1, weight: sug.weightKg ?? 0, repMax: se.repMax)]
            return se
        }
        return (day.name, dayId, exs)
    }
}

struct SessionSummaryData {
    struct ExerciseLine: Identifiable { let id = UUID(); let name: String; let sets: Int; let topSet: String; let isPR: Bool }
    var duration: String
    var totalSets: Int
    var volumeKg: Double
    var prs: [(String, Double)]
    var byMuscle: [String: Int]
    var exercises: [ExerciseLine]
}
