import Foundation
import SwiftData

// SyncEngine — offline-first (contracts §00, spec I2).
// Escritura: el write del usuario ya está en SwiftData; aquí se encola en Outbox y
// se drena FIFO. Éxito → borrar entrada. Red → backoff/retry. 422 → no reintentar,
// marcar syncError local. Lectura: pull incremental GET /api/changes?since=cursor,
// upserts por id; deleted=1 → borrar local. El server SIEMPRE gana.
@MainActor
@Observable
final class SyncEngine {
    private let context: ModelContext
    private var api: APIClient
    private let config: AppConfig

    var isSyncing = false
    var lastError: String?
    var pendingCount: Int = 0

    private let backoff: [TimeInterval] = [2, 8, 30]

    init(context: ModelContext, api: APIClient, config: AppConfig = .shared) {
        self.context = context
        self.api = api
        self.config = config
        refreshPending()
    }

    func setClient(_ client: APIClient) { self.api = client }

    // MARK: - Encolar writes (idempotentes por id)
    func enqueue(endpoint: String, method: String, bodyJSON: String) {
        let item = OutboxItem(createdAt: CBDate.nowMillis(), endpoint: endpoint, method: method, bodyJSON: bodyJSON)
        context.insert(item)
        try? context.save()
        refreshPending()
    }

    func enqueueEncodable<T: Encodable>(endpoint: String, method: String, body: T) {
        let data = (try? JSONEncoder().encode(body)) ?? Data("{}".utf8)
        enqueue(endpoint: endpoint, method: method, bodyJSON: String(data: data, encoding: .utf8) ?? "{}")
    }

    func enqueueRaw(endpoint: String, method: String, dict: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
        enqueue(endpoint: endpoint, method: method, bodyJSON: String(data: data, encoding: .utf8) ?? "{}")
    }

    /// Encola un upsert de workout REEMPLAZANDO cualquier POST pendiente del mismo
    /// id (idempotente por id; evita el pile-up al encolar tras cada set).
    func enqueueWorkoutUpsert(_ dto: WorkoutDTO) {
        let wid = dto.id
        let pending = (try? context.fetch(FetchDescriptor<OutboxItem>())) ?? []
        for item in pending where item.endpoint == "/api/workouts" && item.method == "POST" {
            if let req = try? JSONDecoder().decode(WorkoutRequest.self, from: Data(item.bodyJSON.utf8)),
               req.workout.id == wid {
                context.delete(item)
            }
        }
        enqueueEncodable(endpoint: "/api/workouts", method: "POST", body: WorkoutRequest(workout: dto))
    }

    /// Quita del outbox cualquier POST pendiente de un workout (al descartarlo).
    func removePendingWorkout(id: String) {
        let pending = (try? context.fetch(FetchDescriptor<OutboxItem>())) ?? []
        for item in pending where item.endpoint == "/api/workouts" && item.method == "POST" {
            if let req = try? JSONDecoder().decode(WorkoutRequest.self, from: Data(item.bodyJSON.utf8)),
               req.workout.id == id {
                context.delete(item)
            }
        }
        try? context.save()
        refreshPending()
    }

    private func fetchOutbox(id: String) -> OutboxItem? {
        try? context.fetch(FetchDescriptor<OutboxItem>(predicate: #Predicate { $0.id == id })).first
    }

    private func refreshPending() {
        pendingCount = (try? context.fetchCount(FetchDescriptor<OutboxItem>())) ?? 0
    }

    private var needsResync = false

    // MARK: - Sync completo (drenar + pull)
    func syncNow() async {
        guard config.isConfigured || config.useMockAPI else { return }
        // Coalescing: un trigger durante un sync en curso (p.ej. finishWorkout justo
        // tras saveSet) no se pierde — se corre otra pasada al terminar.
        guard !isSyncing else { needsResync = true; return }
        isSyncing = true
        defer { isSyncing = false; refreshPending() }
        repeat {
            needsResync = false
            await drainOutbox()
            await pullChanges()
        } while needsResync
    }

    // MARK: - Drenar outbox (FIFO, backoff 2s/8s/30s)
    func drainOutbox() async {
        let snapshot = (try? context.fetch(FetchDescriptor<OutboxItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        for stale in snapshot {
            let itemId = stale.id
            // Re-fetch por id: un enqueueWorkoutUpsert/removePendingWorkout durante
            // un `await` previo pudo borrar/reemplazar este item (evita mutar un
            // modelo ya eliminado).
            guard fetchOutbox(id: itemId) != nil else { continue }
            var attempt = 0
            retry: while true {
                guard let item = fetchOutbox(id: itemId) else { break }   // reemplazado mientras esperábamos
                do {
                    try await dispatch(item)
                    if let live = fetchOutbox(id: itemId) { context.delete(live) }  // éxito → borrar
                    try? context.save()
                    break
                } catch let e as APIError where !e.isRetryable {
                    // 422 → descartar y marcar el registro; 401/decoding → dejar en cola sin marcar dato.
                    if let live = fetchOutbox(id: itemId) {
                        live.lastError = e.errorDescription
                        if case .validation = e {
                            markSyncError(for: live, message: e.errorDescription ?? "422")
                            context.delete(live)
                        }
                    }
                    try? context.save()
                    lastError = e.errorDescription
                    break
                } catch {
                    // Red/servidor: reintentar con backoff; agotado → parar (próximo trigger sigue).
                    if let live = fetchOutbox(id: itemId) {
                        live.attempts += 1
                        live.lastError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                        try? context.save()
                        lastError = live.lastError
                    }
                    if attempt < backoff.count {
                        try? await Task.sleep(nanoseconds: UInt64(backoff[attempt] * 1_000_000_000))
                        attempt += 1
                        continue retry
                    }
                    refreshPending()
                    return   // FIFO: no saltar items; se reintenta en el próximo trigger
                }
            }
        }
        refreshPending()
    }

    private func dispatch(_ item: OutboxItem) async throws {
        let data = Data(item.bodyJSON.utf8)
        let dec = JSONDecoder()
        let ep = item.endpoint
        switch (item.method, ep) {
        case ("POST", "/api/meals"):
            _ = try await api.postMeals(try dec.decode(MealsRequest.self, from: data).meals)
        case ("POST", "/api/workouts"):
            _ = try await api.postWorkout(try dec.decode(WorkoutRequest.self, from: data).workout)
        case ("POST", "/api/body-metrics"):
            _ = try await api.postBodyMetrics(try dec.decode(BodyMetricsRequest.self, from: data).metrics)
        case ("POST", "/api/exercises"):
            _ = try await api.postExercises(try dec.decode(ExercisesRequest.self, from: data).exercises)
        case ("PUT", "/api/goals"):
            _ = try await api.putGoals(try dec.decode(GoalsRequest.self, from: data).goals)
        case ("PUT", "/api/program"):
            let r = try dec.decode(ProgramUpdateRequest.self, from: data)
            _ = try await api.putProgram(startDate: r.start_date, json: r.json)
        default:
            if item.method == "PATCH", ep.hasPrefix("/api/meals/") {
                let id = String(ep.dropFirst("/api/meals/".count))
                let fields = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                _ = try await api.patchMeal(id: id, fields: fields)
            } else if item.method == "DELETE", ep.hasPrefix("/api/meals/") {
                _ = try await api.deleteMeal(id: String(ep.dropFirst("/api/meals/".count)))
            } else if item.method == "DELETE", ep.hasPrefix("/api/workouts/") {
                _ = try await api.deleteWorkout(id: String(ep.dropFirst("/api/workouts/".count)))
            } else if item.method == "PUT", ep.hasPrefix("/api/days/") {
                let date = String(ep.dropFirst("/api/days/".count))
                let r = try dec.decode(DayUpdateRequest.self, from: data)
                _ = try await api.putDay(date: date, loggingComplete: r.logging_complete)
            } else {
                throw APIError.validation("Endpoint desconocido en outbox: \(item.method) \(ep)")
            }
        }
    }

    private func markSyncError(for item: OutboxItem, message: String) {
        // Mejor esfuerzo: marcar el registro local con syncError para mostrar en Ajustes.
        if item.endpoint == "/api/meals", let req = try? JSONDecoder().decode(MealsRequest.self, from: Data(item.bodyJSON.utf8)) {
            for m in req.meals { if let local = fetchMeal(id: m.id) { local.syncError = message } }
        } else if item.endpoint == "/api/workouts", let req = try? JSONDecoder().decode(WorkoutRequest.self, from: Data(item.bodyJSON.utf8)) {
            if let local = fetchWorkout(id: req.workout.id) { local.syncError = message }
        }
    }

    // MARK: - Pull incremental
    func pullChanges() async {
        do {
            let since = config.syncCursor
            let changes = try await api.getChanges(since: since)
            apply(changes)
            config.syncCursor = changes.cursor
            config.lastSyncAt = Date()
            lastError = nil
        } catch let e as APIError {
            lastError = e.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func apply(_ c: ChangesResponse) {
        for dto in c.exercises { applyExercise(dto) }
        for dto in c.meals { applyMeal(dto) }
        for dto in c.workouts { applyWorkout(dto) }
        for dto in c.sets { applySet(dto) }
        for dto in c.body_metrics { applyBodyMetric(dto) }
        for dto in c.program { applyProgram(dto) }
        for kv in c.goals { applyGoal(kv) }
        for dto in c.day_flags { applyDayFlag(dto) }
        try? context.save()
    }

    // MARK: - Fetch helpers
    private func fetchMeal(id: String) -> Meal? {
        try? context.fetch(FetchDescriptor<Meal>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchWorkout(id: String) -> Workout? {
        try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchSet(id: String) -> WorkoutSet? {
        try? context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchExercise(id: String) -> Exercise? {
        try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchBodyMetric(id: String) -> BodyMetric? {
        try? context.fetch(FetchDescriptor<BodyMetric>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Apply per entity (server gana)
    private func applyMeal(_ d: MealDTO) {
        let local = fetchMeal(id: d.id)
        if d.deleted == 1 { if let local { context.delete(local) }; return }
        let m = local ?? Meal(id: d.id, ts: d.ts, date: d.date, mealGroupId: d.meal_group_id, name: d.name,
                              quantityG: d.quantity_g, kcal: d.kcal, proteinG: d.protein_g, carbsG: d.carbs_g,
                              fatG: d.fat_g, fiberG: d.fiber_g, source: MealSource(rawValue: d.source) ?? .manual,
                              confidence: d.confidence, portionBasis: PortionBasis(rawValue: d.portion_basis) ?? .estimated)
        m.ts = d.ts; m.date = d.date; m.mealGroupId = d.meal_group_id; m.name = d.name; m.quantityG = d.quantity_g
        m.kcal = d.kcal; m.proteinG = d.protein_g; m.carbsG = d.carbs_g; m.fatG = d.fat_g; m.fiberG = d.fiber_g
        m.sourceRaw = d.source; m.confidence = d.confidence; m.portionBasisRaw = d.portion_basis
        m.fdcId = d.fdc_id; m.offId = d.off_id; m.notes = d.notes
        m.per100g = d.per_100g?.value   // server-gana: si el server lo anula, se limpia local
        m.updatedAt = d.updated_at ?? m.updatedAt; m.deleted = false; m.dirty = false; m.syncError = nil
        if local == nil { context.insert(m) }
    }
    private func applyExercise(_ d: ExerciseDTO) {
        let local = fetchExercise(id: d.id)
        if d.deleted == 1 { if let local { context.delete(local) }; return }
        let e = local ?? Exercise(id: d.id, name: d.name, muscleGroup: MuscleGroup(rawValue: d.muscle_group) ?? .chest,
                                  pattern: MovementPattern(rawValue: d.pattern) ?? .isolation,
                                  equipment: Equipment(rawValue: d.equipment) ?? .barbell, incrementKg: d.increment_kg)
        e.name = d.name; e.muscleGroupRaw = d.muscle_group; e.patternRaw = d.pattern
        e.equipmentRaw = d.equipment; e.incrementKg = d.increment_kg; e.updatedAt = d.updated_at ?? e.updatedAt; e.deleted = false
        if local == nil { context.insert(e) }
    }
    private func applyWorkout(_ d: WorkoutDTO) {
        let local = fetchWorkout(id: d.id)
        if d.deleted == 1 { if let local { context.delete(local) }; return }
        let w = local ?? Workout(id: d.id, tsStart: d.ts_start, date: d.date)
        w.tsStart = d.ts_start; w.tsEnd = d.ts_end; w.date = d.date; w.programDayId = d.program_day_id
        w.notes = d.notes; w.updatedAt = d.updated_at ?? w.updatedAt; w.deleted = false; w.dirty = false
        w.syncError = nil
        w.finished = d.ts_end != nil
        if local == nil { context.insert(w) }
        for s in (d.sets ?? []) { applySet(s) }
    }
    private func applySet(_ d: SetDTO) {
        let local = fetchSet(id: d.id)
        if d.deleted == 1 { if let local { context.delete(local) }; return }
        let s = local ?? WorkoutSet(id: d.id, workoutId: d.workout_id, exerciseId: d.exercise_id,
                                    setNumber: d.set_number, weightKg: d.weight_kg, reps: d.reps, rir: d.rir)
        s.workoutId = d.workout_id; s.exerciseId = d.exercise_id; s.setNumber = d.set_number
        s.weightKg = d.weight_kg; s.reps = d.reps; s.rir = d.rir; s.isWarmup = d.is_warmup == 1
        s.e1rmKg = d.e1rm_kg; s.updatedAt = d.updated_at ?? s.updatedAt; s.deleted = false; s.dirty = false
        if local == nil { context.insert(s) }
    }
    private func applyBodyMetric(_ d: BodyMetricDTO) {
        let local = fetchBodyMetric(id: d.id)
        if d.deleted == 1 { if let local { context.delete(local) }; return }
        let b = local ?? BodyMetric(id: d.id, ts: d.ts, date: d.date, type: BodyMetricType(rawValue: d.type) ?? .weightKg,
                                    value: d.value, source: MetricSource(rawValue: d.source) ?? .healthkit)
        b.ts = d.ts; b.date = d.date; b.typeRaw = d.type; b.value = d.value; b.sourceRaw = d.source
        b.updatedAt = d.updated_at ?? b.updatedAt; b.deleted = false; b.dirty = false
        if local == nil { context.insert(b) }
    }
    private func applyProgram(_ d: ProgramDTO) {
        // El feed de /api/changes trae varias filas al hacer update_program (la vieja
        // con active=0 y la nueva con active=1). RESPETAR d.active/d.deleted; NO
        // desactivar en bloque por orden de llegada. Solo la fila con active=1
        // desactiva a las demás. (schema D1: active default 1 → nil se trata activo.)
        let existing = (try? context.fetch(FetchDescriptor<ProgramModel>())) ?? []
        let jsonStr = (try? String(data: JSONEncoder().encode(d.json), encoding: .utf8) ?? nil) ?? "{}"
        let isActive = (d.active ?? 1) == 1
        let isDeleted = d.deleted == 1

        if let local = existing.first(where: { $0.id == d.id }) {
            if isDeleted { context.delete(local) }
            else {
                local.startDate = d.start_date; local.json = jsonStr
                local.updatedAt = d.updated_at ?? local.updatedAt
                local.active = isActive; local.deleted = false
            }
        } else if !isDeleted {
            context.insert(ProgramModel(id: d.id, active: isActive, startDate: d.start_date,
                                        json: jsonStr, updatedAt: d.updated_at ?? 0, deleted: false))
        }

        // Invariante "un solo programa activo": solo si ESTA fila queda activa.
        if isActive && !isDeleted {
            for p in existing where p.id != d.id { p.active = false }
        }
    }
    private func applyGoal(_ kv: ChangesResponse.GoalKV) {
        let key = kv.key
        let local = try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.key == key })).first
        if let g = local { g.value = kv.value; g.updatedAt = kv.updated_at ?? g.updatedAt; g.dirty = false }
        else { context.insert(Goal(key: kv.key, value: kv.value, updatedAt: kv.updated_at ?? 0, dirty: false)) }
    }
    private func applyDayFlag(_ d: DayFlagDTO) {
        let date = d.date
        let local = try? context.fetch(FetchDescriptor<DayFlag>(predicate: #Predicate { $0.date == date })).first
        if let f = local { f.loggingComplete = d.logging_complete == 1; f.updatedAt = d.updated_at ?? f.updatedAt; f.dirty = false }
        else { context.insert(DayFlag(date: d.date, loggingComplete: d.logging_complete == 1, updatedAt: d.updated_at ?? 0, dirty: false)) }
    }
}
