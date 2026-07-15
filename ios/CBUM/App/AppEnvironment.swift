import Foundation
import SwiftUI
import SwiftData

// AppEnvironment — raíz de dependencias. Crea el ModelContainer, elige el API
// client (mock/live intercambiable), y expone operaciones write-through:
// SwiftData primero (UI instantánea) → Outbox → (HealthKit tras save local).
@MainActor
@Observable
final class AppEnvironment {
    let container: ModelContainer
    let context: ModelContext
    let config: AppConfig
    let sync: SyncEngine
    let health: HealthKitService
    private(set) var api: APIClient

    init(inMemory: Bool = false) {
        let schema = Schema([
            Meal.self, Exercise.self, Workout.self, WorkoutSet.self,
            BodyMetric.self, DayFlag.self, ProgramModel.self, Goal.self, OutboxItem.self,
        ])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        // swiftlint:disable:next force_try
        container = try! ModelContainer(for: schema, configurations: [cfg])
        context = container.mainContext
        let appConfig = AppConfig.shared
        config = appConfig
        let client: APIClient = appConfig.useMockAPI ? MockAPIClient() : LiveAPIClient(config: appConfig)
        api = client
        sync = SyncEngine(context: context, api: client, config: appConfig)
        health = HealthKitService()
    }

    /// Cambia entre mock y live en caliente (Ajustes). Resetea el cursor y purga
    /// los datos ya sincronizados: el cursor es compartido y el mock arranca su
    /// reloj en "ahora", así que sin reset el primer pull contra el backend real
    /// saltaría todo el histórico; y los datos semilla del mock no deben mezclarse
    /// con los reales. El Outbox (writes pendientes) se conserva.
    func switchClient(useMock: Bool) {
        config.useMockAPI = useMock
        config.syncCursor = 0
        purgeSyncedData()
        let client: APIClient = useMock ? MockAPIClient() : LiveAPIClient(config: config)
        api = client
        sync.setClient(client)
    }

    /// Borra las entidades traídas por sync (no el Outbox) para un re-pull limpio.
    private func purgeSyncedData() {
        try? context.delete(model: Meal.self)
        try? context.delete(model: Workout.self)
        try? context.delete(model: WorkoutSet.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: BodyMetric.self)
        try? context.delete(model: DayFlag.self)
        try? context.delete(model: ProgramModel.self)
        try? context.delete(model: Goal.self)
        try? context.save()
    }

    // MARK: - Triggers de sync
    func syncNow() { Task { await sync.syncNow() } }

    // MARK: - Write-through: nutrición
    func logMeal(_ meal: Meal, writeHealth: Bool = true) {
        meal.dirty = true
        context.insert(meal)
        try? context.save()
        sync.enqueueEncodable(endpoint: "/api/meals", method: "POST", body: MealsRequest(meals: [meal.toDTO()]))
        if writeHealth {
            let id = meal.id, ts = meal.ts, macros = meal.macros
            Task { await health.writeMeal(id: id, tsISO: ts, macros: macros) }
        }
        syncNow()
    }

    func updateMealQuantity(_ meal: Meal, quantityG: Double) {
        meal.quantityG = quantityG
        if let per = meal.per100g {
            let s = per.scaled(toGrams: quantityG)
            meal.kcal = s.kcal; meal.proteinG = s.protein_g; meal.carbsG = s.carbs_g; meal.fatG = s.fat_g; meal.fiberG = s.fiber_g
        }
        meal.dirty = true
        try? context.save()
        sync.enqueueRaw(endpoint: "/api/meals/\(meal.id)", method: "PATCH", dict: ["quantity_g": quantityG])
        let id = meal.id, ts = meal.ts, macros = meal.macros
        Task { await health.writeMeal(id: id, tsISO: ts, macros: macros) }
        syncNow()
    }

    func updateMealMacros(_ meal: Meal, macros: Macros) {
        meal.kcal = macros.kcal; meal.proteinG = macros.protein_g; meal.carbsG = macros.carbs_g
        meal.fatG = macros.fat_g; meal.fiberG = macros.fiber_g
        meal.portionBasisRaw = PortionBasis.estimated.rawValue
        meal.dirty = true
        try? context.save()
        // Incluir portion_basis (edición manual → estimada) y fiber para que el
        // pull server-gana no revierta el badge ni el % pesado del día.
        var patch: [String: Any] = ["kcal": macros.kcal, "protein_g": macros.protein_g,
                                    "carbs_g": macros.carbs_g, "fat_g": macros.fat_g,
                                    "portion_basis": PortionBasis.estimated.rawValue]
        if let fiber = macros.fiber_g { patch["fiber_g"] = fiber }
        sync.enqueueRaw(endpoint: "/api/meals/\(meal.id)", method: "PATCH", dict: patch)
        let id = meal.id, ts = meal.ts
        Task { await health.writeMeal(id: id, tsISO: ts, macros: macros) }
        syncNow()
    }

    func deleteMeal(_ meal: Meal) {
        meal.deleted = true
        try? context.save()
        sync.enqueue(endpoint: "/api/meals/\(meal.id)", method: "DELETE", bodyJSON: "{}")
        let id = meal.id
        Task { await health.deleteSamples(cbumId: id) }
        syncNow()
    }

    // MARK: - Write-through: entreno
    func saveSet(_ set: WorkoutSet) {
        // e1RM en la instancia recibida (el caller lee set.e1rmKg tras esta llamada).
        set.e1rmKg = FormulasKit.e1rm(weightKg: set.weightKg, reps: set.reps, rir: set.rir, isWarmup: set.isWarmup)
        set.dirty = true
        // Editar un set ya guardado = update-in-place (antes se descartaba la
        // instancia nueva y el server recibía los valores viejos).
        if let existing = fetchSet(id: set.id) {
            existing.exerciseId = set.exerciseId; existing.setNumber = set.setNumber
            existing.weightKg = set.weightKg; existing.reps = set.reps; existing.rir = set.rir
            existing.isWarmup = set.isWarmup; existing.e1rmKg = set.e1rmKg; existing.dirty = true
        } else {
            context.insert(set)
        }
        try? context.save()
        // Sync incremental: encolar el workout completo (upsert idempotente) tras
        // CADA set, para no perder la sesión si no se finaliza el mismo día.
        if let w = fetchWorkout(id: set.workoutId) {
            sync.enqueueWorkoutUpsert(w.toDTO(sets: fetchSets(workoutId: w.id).map { $0.toDTO() }))
        }
        syncNow()
    }

    /// Descarta el workout activo: borra sets locales, quita del outbox cualquier
    /// POST pendiente de ese workout y, si ya pudo postearse, encola un DELETE.
    /// (Antes solo marcaba w.deleted local → el POST pendiente lo revivía en el
    /// server y el siguiente pull lo resucitaba.)
    func discardWorkout(_ workout: Workout) {
        let wid = workout.id
        workout.deleted = true
        for s in fetchSets(workoutId: wid) { s.deleted = true }
        try? context.save()
        sync.removePendingWorkout(id: wid)
        // Si el workout ya existía en el server (updatedAt>0), asegurar el borrado.
        if workout.updatedAt > 0 {
            sync.enqueue(endpoint: "/api/workouts/\(wid)", method: "DELETE", bodyJSON: "{}")
        }
        syncNow()
    }

    /// Al arrancar: rescata workouts no finalizados de días pasados. Con sets → se
    /// cierran y encolan (ninguna sesión queda huérfana aunque no vuelvas el mismo
    /// día); vacíos → se borran (basura). El de HOY lo resucita la Sesión.
    func recoverUnfinishedWorkouts() {
        let today = CBDate.day()
        let unfinished = ((try? context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.finished == false && $0.deleted == false }))) ?? [])
        var changed = false
        for w in unfinished where w.date < today {
            let sets = fetchSets(workoutId: w.id)
            if sets.isEmpty {
                w.deleted = true; changed = true   // sesión vacía de un día pasado: descartar
                continue
            }
            // Los sets no llevan ts propio → se usa ts_start como ts_end aproximado.
            w.finished = true
            w.tsEnd = w.tsEnd ?? w.tsStart
            changed = true
            sync.enqueueWorkoutUpsert(w.toDTO(sets: sets.map { $0.toDTO() }))
        }
        if changed { try? context.save() }
        syncNow()
    }

    /// Finaliza el workout: ts_end, POST completo (outbox), HKWorkout.
    func finishWorkout(_ workout: Workout) {
        workout.tsEnd = CBDate.ts()
        workout.finished = true
        workout.dirty = true
        try? context.save()
        let sets = fetchSets(workoutId: workout.id)
        let dto = workout.toDTO(sets: sets.map { $0.toDTO() })
        sync.enqueueWorkoutUpsert(dto)   // reemplaza el parcial pendiente por el final (con ts_end)
        let id = workout.id, start = workout.tsStart, end = workout.tsEnd ?? CBDate.ts()
        Task { await health.writeWorkout(id: id, startISO: start, endISO: end) }
        syncNow()
    }

    // MARK: - Write-through: días / goals
    func setDayFlag(date: String, complete: Bool) {
        let flag = fetchDayFlag(date: date) ?? {
            let f = DayFlag(date: date, loggingComplete: complete); context.insert(f); return f
        }()
        flag.loggingComplete = complete
        flag.dirty = true
        try? context.save()
        sync.enqueueEncodable(endpoint: "/api/days/\(date)", method: "PUT", body: DayUpdateRequest(logging_complete: complete))
        syncNow()
    }

    func saveGoals(_ goals: [String: String]) {
        for (k, v) in goals {
            if let g = fetchGoal(key: k) { g.value = v; g.dirty = true }
            else { context.insert(Goal(key: k, value: v)) }
        }
        try? context.save()
        sync.enqueueEncodable(endpoint: "/api/goals", method: "PUT", body: GoalsRequest(goals: goals))
        syncNow()
    }

    // MARK: - HealthKit → API
    func importFromHealthKit() {
        Task {
            let weight = await health.readWeight()
            let totals = await health.readDailyTotals()
            let sleep = await health.readSleep()
            // Reconciliar ids con los locales por (type,ts,source): steps/sleep se
            // recomputan con UUID nuevo en cada import; reusar el id estable evita
            // que el pull posterior (que aplica por id) inserte un duplicado.
            let all = (weight + totals + sleep).map { reconcileMetricId($0) }
            guard !all.isEmpty else { return }
            for dto in all { upsertLocalMetric(dto) }
            try? context.save()
            sync.enqueueEncodable(endpoint: "/api/body-metrics", method: "POST", body: BodyMetricsRequest(metrics: all))
            await sync.syncNow()
        }
    }

    private func reconcileMetricId(_ d: BodyMetricDTO) -> BodyMetricDTO {
        let type = d.type, ts = d.ts, source = d.source
        if let existing = (try? context.fetch(FetchDescriptor<BodyMetric>(
            predicate: #Predicate { $0.typeRaw == type && $0.ts == ts && $0.sourceRaw == source })))?.first {
            var d = d; d.id = existing.id; return d
        }
        return d
    }

    private func upsertLocalMetric(_ d: BodyMetricDTO) {
        if let m = fetchSet(metricId: d.id) { m.value = d.value; m.dirty = true }
        else {
            context.insert(BodyMetric(id: d.id, ts: d.ts, date: d.date,
                                      type: BodyMetricType(rawValue: d.type) ?? .weightKg,
                                      value: d.value, source: MetricSource(rawValue: d.source) ?? .healthkit))
        }
    }
    private func fetchSet(metricId id: String) -> BodyMetric? {
        try? context.fetch(FetchDescriptor<BodyMetric>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Fetch helpers
    func fetchSet(id: String) -> WorkoutSet? {
        try? context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.id == id })).first
    }
    func fetchWorkout(id: String) -> Workout? {
        try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })).first
    }
    func fetchSets(workoutId: String) -> [WorkoutSet] {
        let sets = (try? context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.workoutId == workoutId && $0.deleted == false }))) ?? []
        return sets.sorted { $0.setNumber < $1.setNumber }
    }
    func fetchDayFlag(date: String) -> DayFlag? {
        try? context.fetch(FetchDescriptor<DayFlag>(predicate: #Predicate { $0.date == date })).first
    }
    func fetchGoal(key: String) -> Goal? {
        try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.key == key })).first
    }
    func activeProgram() -> ProgramModel? {
        try? context.fetch(FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.active == true && $0.deleted == false })).first
    }
    func allExercises() -> [Exercise] {
        ((try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.deleted == false }))) ?? [])
            .sorted { $0.name < $1.name }
    }
}
