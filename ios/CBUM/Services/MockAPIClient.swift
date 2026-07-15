import Foundation

// Mock local del API client (contracts §3). Respeta los shapes exactos y calcula
// los endpoints derivados con FormulasKit. Intercambiable con LiveAPIClient por
// `AppConfig.useMockAPI`. Sirve para desarrollar la UI sin backend desplegado.
// Datos semilla realistas de gym (kg, RIR, macros).
final class MockAPIClient: APIClient {
    // Estado en memoria
    private var meals: [MealDTO] = []
    private var workouts: [WorkoutDTO] = []
    private var exercises: [ExerciseDTO] = []
    private var bodyMetrics: [BodyMetricDTO] = []
    private var dayFlags: [String: DayFlagDTO] = [:]
    private var goals: [String: String] = [:]
    private var programDTO: ProgramDTO?
    private var clock = CBDate.nowMillis()

    private let cal = Calendar.bogota

    init() { seed() }

    private func bump() -> Int { clock += 1; return clock }

    // MARK: Seed
    private func seed() {
        goals = [
            "target_kcal": "2650", "target_protein_g": "190", "target_carbs_g": "260",
            "target_fat_g": "78", "goal_weight_kg": "80", "goal_rate_kg_per_week": "-0.35",
            "sex": "m", "age": "30", "height_cm": "178", "activity_factor": "1.5",
        ]
        exercises = [
            ex("barbell-bench-press", "Press banca con barra", "chest", "horizontal_push", "barbell", 2.5),
            ex("barbell-row", "Remo con barra", "back", "horizontal_pull", "barbell", 2.5),
            ex("overhead-press", "Press militar", "shoulders", "vertical_push", "barbell", 2.5),
            ex("lat-pulldown", "Jalón al pecho", "back", "vertical_pull", "cable", 5.0),
            ex("incline-db-press", "Press inclinado mancuerna", "chest", "horizontal_push", "dumbbell", 2.0),
            ex("barbell-squat", "Sentadilla con barra", "quads", "squat", "barbell", 5.0),
            ex("romanian-deadlift", "Peso muerto rumano", "hamstrings", "hinge", "barbell", 5.0),
            ex("leg-press", "Prensa de pierna", "quads", "squat", "machine", 5.0),
            ex("db-curl", "Curl mancuerna", "biceps", "isolation", "dumbbell", 2.0),
            ex("triceps-pushdown", "Extensión tríceps polea", "triceps", "isolation", "cable", 5.0),
        ]
        let program = ProgramJSON(
            version: 1, name: "Upper/Lower 4d",
            days: [
                ProgramDay(id: "upper_a", name: "Upper A", exercises: [
                    ProgramExercise(exercise_id: "barbell-bench-press", sets: 4, rep_range: [6, 8], target_rir: 2, rest_sec: 180, notes: "pausa en pecho"),
                    ProgramExercise(exercise_id: "barbell-row", sets: 4, rep_range: [8, 10], target_rir: 2, rest_sec: 150, notes: nil),
                    ProgramExercise(exercise_id: "overhead-press", sets: 3, rep_range: [6, 8], target_rir: 2, rest_sec: 150, notes: nil),
                    ProgramExercise(exercise_id: "lat-pulldown", sets: 3, rep_range: [10, 12], target_rir: 1, rest_sec: 120, notes: nil),
                    ProgramExercise(exercise_id: "db-curl", sets: 3, rep_range: [10, 12], target_rir: 1, rest_sec: 90, notes: nil),
                    ProgramExercise(exercise_id: "triceps-pushdown", sets: 3, rep_range: [10, 12], target_rir: 1, rest_sec: 90, notes: nil),
                ]),
                ProgramDay(id: "lower_a", name: "Lower A", exercises: [
                    ProgramExercise(exercise_id: "barbell-squat", sets: 4, rep_range: [6, 8], target_rir: 2, rest_sec: 210, notes: nil),
                    ProgramExercise(exercise_id: "romanian-deadlift", sets: 3, rep_range: [8, 10], target_rir: 2, rest_sec: 180, notes: nil),
                    ProgramExercise(exercise_id: "leg-press", sets: 3, rep_range: [10, 12], target_rir: 1, rest_sec: 150, notes: nil),
                ]),
                ProgramDay(id: "upper_b", name: "Upper B", exercises: [
                    ProgramExercise(exercise_id: "incline-db-press", sets: 4, rep_range: [8, 10], target_rir: 2, rest_sec: 150, notes: nil),
                    ProgramExercise(exercise_id: "lat-pulldown", sets: 4, rep_range: [8, 10], target_rir: 2, rest_sec: 150, notes: nil),
                    ProgramExercise(exercise_id: "overhead-press", sets: 3, rep_range: [8, 10], target_rir: 2, rest_sec: 150, notes: nil),
                ]),
                ProgramDay(id: "lower_b", name: "Lower B", exercises: [
                    ProgramExercise(exercise_id: "barbell-squat", sets: 3, rep_range: [8, 10], target_rir: 2, rest_sec: 180, notes: nil),
                    ProgramExercise(exercise_id: "romanian-deadlift", sets: 4, rep_range: [6, 8], target_rir: 2, rest_sec: 210, notes: nil),
                ]),
            ],
            schedule: ["upper_a", "lower_a", "rest", "upper_b", "lower_b", "rest", "rest"]
        )
        let startDay = CBDate.day(cal.date(byAdding: .day, value: -14, to: Date()) ?? Date())
        programDTO = ProgramDTO(id: "prog-1", start_date: startDay,
                                json: program, active: 1, updated_at: bump(), deleted: 0)

        // Histórico multi-año (~5 años, semanal): de ~92 kg (2021) a ~83 kg. Ejercita
        // los rangos 1A/TODO y demuestra el fix del Bug 1 (chart de peso multi-año).
        var histW = 92.0
        for wk in stride(from: 260, through: 4, by: -1) {
            let d = cal.date(byAdding: .day, value: -wk * 7, to: Date()) ?? Date()
            histW -= 0.035
            let wobble = Double((wk * 7) % 5 - 2) / 20.0   // determinista, sin Date.random en seed
            bodyMetrics.append(bm("weight_kg", value: ((histW + wobble) * 10).rounded() / 10, date: d))
        }
        // Pesajes últimos 24 días (tendencia bajando ~0.03/día), un par de días sin pesaje.
        var base = 83.2
        for i in stride(from: 24, through: 0, by: -1) {
            if i == 5 || i == 12 { base -= 0.03; continue } // días sin pesaje
            let d = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            base -= Double(((24 - i) * 3) % 6) / 100.0
            bodyMetrics.append(bm("weight_kg", value: (base * 10).rounded() / 10, date: d))
        }
        // Pasos de hoy (informativo)
        bodyMetrics.append(bm("steps", value: 8420, date: Date()))
        // Sueño/HRV/RHR + composición (V2). IDs deterministas por (type,date).
        seedRecovery()
        seedComposition()

        // Comidas de hoy (mezcla pesado/etiqueta/estimado)
        let today = CBDate.day()
        // IDs deterministas: el seed corre en cada launch; con UUID() aleatorios
        // el upsert del sync duplicaba todo (bug: 7.320 kcal de avenas repetidas).
        let g1 = "mock-group-\(today)-desayuno", g2 = "mock-group-\(today)-almuerzo", g3 = "mock-group-\(today)-cena"
        meals = [
            meal("Avena + whey + banano", today, g1, kcal: 520, p: 42, c: 68, f: 9, source: "label", conf: 0.95, basis: "weighed", h: 7),
            meal("Pollo + arroz + aguacate", today, g2, kcal: 642, p: 48, c: 71, f: 18, source: "barcode", conf: 0.9, basis: "weighed", h: 13),
            meal("Almuerzo restaurante", today, g3, kcal: 668, p: 52, c: 21, f: 31, source: "photo", conf: 0.55, basis: "estimated", h: 16, fdc: 173410),
        ]
        // Días completos previos + intake para TDEE adaptativo
        for i in 1...16 {
            let d = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            let ds = CBDate.day(d)
            dayFlags[ds] = DayFlagDTO(date: ds, logging_complete: 1, updated_at: bump())
            let gg = "mock-group-\(ds)"
            meals.append(meal("Día \(ds)", ds, gg, kcal: 2500 + Double(Int.random(in: -120...120)),
                              p: 185, c: 250, f: 76, source: "manual", conf: 0.8, basis: "weighed", h: 20))
        }

        // Workouts previos para sugerencias/progreso (upper_a: bench, row)
        seedWorkoutHistory()
    }

    private func seedWorkoutHistory() {
        // 3 sesiones de bench progresando: 77.5 → 80 → 80(top-set fallo parcial)
        let benchWeights: [(daysAgo: Int, w: Double, reps: [Int])] = [
            (14, 77.5, [8, 8, 8, 8]), (7, 80.0, [8, 8, 8, 7]),
        ]
        for s in benchWeights {
            let d = cal.date(byAdding: .day, value: -s.daysAgo, to: Date()) ?? Date()
            var sets: [SetDTO] = []
            for (i, r) in s.reps.enumerated() {
                sets.append(makeSet(workoutId: "w-bench-\(s.daysAgo)", ex: "barbell-bench-press",
                                    n: i + 1, w: s.w, reps: r, rir: 2))
            }
            workouts.append(WorkoutDTO(id: "w-bench-\(s.daysAgo)",
                ts_start: CBDate.ts(d), ts_end: CBDate.ts(d.addingTimeInterval(3600)),
                date: CBDate.day(d), program_day_id: "upper_a", notes: nil, sets: sets,
                updated_at: bump(), deleted: 0))
        }
    }

    // Sueño con fases + RHR + HRV (V2). Historial de 60 días con baselines estables
    // (rhr 58, hrv 62, midpoint 2.8) para reproducir los números del delta §R2, y HOY
    // el vector-trampa (sleep 6.95 + rhr +5.2 + hrv −22.6 → caution).
    private func seedRecovery() {
        for i in 1...60 {
            let d = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            let w = Double((i * 13) % 7 - 3) / 20.0   // determinista ∈ [-0.15, 0.15]
            let deep = 1.05 + w * 0.5
            let rem = 1.45 + w
            let core = 4.35 - w * 0.5
            let awake = 0.55 + abs(w) * 0.4
            addPhaseNight(date: d, deep: deep, rem: rem, core: core, awake: awake,
                          total: deep + rem + core, inbed: deep + rem + core + awake + 0.25, midpoint: 2.8)
            bodyMetrics.append(bm("resting_hr", value: 58, date: d))
            bodyMetrics.append(bm("hrv_ms", value: 62, date: d))
            bodyMetrics.append(bm("respiratory_rate", value: 14.2, date: d))
        }
        let today = Date()
        addPhaseNight(date: today, deep: 1.20, rem: 1.55, core: 4.20, awake: 0.80,
                      total: 6.95, inbed: 7.75, midpoint: 3.4)
        bodyMetrics.append(bm("resting_hr", value: 61, date: today))
        bodyMetrics.append(bm("hrv_ms", value: 48, date: today))
        bodyMetrics.append(bm("respiratory_rate", value: 15.1, date: today))
    }

    private func addPhaseNight(date d: Date, deep: Double, rem: Double, core: Double,
                               awake: Double, total: Double, inbed: Double, midpoint: Double) {
        func r2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
        bodyMetrics.append(bm("sleep_hours", value: r2(total), date: d))
        bodyMetrics.append(bm("sleep_deep_hours", value: r2(deep), date: d))
        bodyMetrics.append(bm("sleep_rem_hours", value: r2(rem), date: d))
        bodyMetrics.append(bm("sleep_core_hours", value: r2(core), date: d))
        bodyMetrics.append(bm("sleep_awake_hours", value: r2(awake), date: d))
        bodyMetrics.append(bm("sleep_inbed_hours", value: r2(inbed), date: d))
        bodyMetrics.append(bm("sleep_midpoint_hour", value: midpoint, date: d))
    }

    // Composición (báscula): recomposición grasa%↓ + masa magra↑, semanal como el peso.
    private func seedComposition() {
        var bf = 16.8, lean = 68.5
        for wk in stride(from: 12, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -wk * 7, to: Date()) ?? Date()
            bf -= 0.12; lean += 0.18
            bodyMetrics.append(bm("body_fat_pct", value: (bf * 10).rounded() / 10, date: d))
            bodyMetrics.append(bm("lean_mass_kg", value: (lean * 10).rounded() / 10, date: d))
        }
    }

    // MARK: Helpers seed
    private func ex(_ id: String, _ n: String, _ mg: String, _ p: String, _ eq: String, _ inc: Double) -> ExerciseDTO {
        ExerciseDTO(id: id, name: n, muscle_group: mg, pattern: p, equipment: eq, increment_kg: inc, updated_at: bump(), deleted: 0)
    }
    private func bm(_ type: String, value: Double, date d: Date) -> BodyMetricDTO {
        BodyMetricDTO(id: "mock-bm-\(type)-\(CBDate.day(d))", ts: CBDate.ts(d), date: CBDate.day(d), type: type,
                      value: value, source: "healthkit", updated_at: bump(), deleted: 0)
    }
    private func meal(_ name: String, _ date: String, _ group: String, kcal: Double, p: Double, c: Double, f: Double,
                      source: String, conf: Double, basis: String, h: Int, fdc: Int? = nil) -> MealDTO {
        let d = (CBDate.date(fromDay: date) ?? Date()).addingTimeInterval(Double(h) * 3600)
        return MealDTO(id: "mock-meal-\(date)-h\(h)", ts: CBDate.ts(d), date: date, meal_group_id: group, name: name,
                       quantity_g: basis == "weighed" ? 250 : nil, kcal: kcal, protein_g: p, carbs_g: c, fat_g: f,
                       fiber_g: 6, per_100g: nil, source: source, confidence: conf, portion_basis: basis,
                       fdc_id: fdc, off_id: nil, notes: nil, updated_at: bump(), deleted: 0)
    }
    private func makeSet(workoutId: String, ex: String, n: Int, w: Double, reps: Int, rir: Int) -> SetDTO {
        let e = FormulasKit.e1rm(weightKg: w, reps: reps, rir: rir, isWarmup: false)
        return SetDTO(id: "mock-set-\(workoutId)-\(n)", workout_id: workoutId, exercise_id: ex, set_number: n,
                      weight_kg: w, reps: reps, rir: rir, is_warmup: 0, e1rm_kg: e, updated_at: bump(), deleted: 0)
    }

    // MARK: - APIClient (writes = upsert por id)
    func health() async throws -> HealthResponse { HealthResponse(ok: true, version: "mock-1") }

    func postMeals(_ ms: [MealDTO]) async throws -> UpsertedResponse {
        for m in ms { upsertMeal(m) }
        return UpsertedResponse(upserted: ms.count)
    }
    private func upsertMeal(_ m: MealDTO) {
        var m = m; m.updated_at = bump()
        if let i = meals.firstIndex(where: { $0.id == m.id }) { meals[i] = m } else { meals.append(m) }
    }
    func patchMeal(id: String, fields: [String: Any]) async throws -> MealDTO {
        guard let i = meals.firstIndex(where: { $0.id == id }) else { throw APIError.validation("meal no existe") }
        var m = meals[i]
        if let q = fields["quantity_g"] as? Double ?? (fields["quantity_g"] as? Int).map(Double.init) {
            m.quantity_g = q
            if let per = m.per_100g?.value {
                let s = per.scaled(toGrams: q)
                m.kcal = s.kcal; m.protein_g = s.protein_g; m.carbs_g = s.carbs_g; m.fat_g = s.fat_g; m.fiber_g = s.fiber_g
            }
        }
        for (k, v) in fields {
            switch k {
            case "kcal": m.kcal = (v as? Double) ?? m.kcal
            case "protein_g": m.protein_g = (v as? Double) ?? m.protein_g
            case "carbs_g": m.carbs_g = (v as? Double) ?? m.carbs_g
            case "fat_g": m.fat_g = (v as? Double) ?? m.fat_g
            case "name": m.name = (v as? String) ?? m.name
            default: break
            }
        }
        m.updated_at = bump()
        meals[i] = m
        return m
    }
    func deleteMeal(id: String) async throws -> OkResponse {
        if let i = meals.firstIndex(where: { $0.id == id }) { meals[i].deleted = 1; meals[i].updated_at = bump() }
        return OkResponse(ok: true)
    }
    func postWorkout(_ w: WorkoutDTO) async throws -> WorkoutDTO {
        var w = w; w.updated_at = bump()
        // server calcula e1rm por set (§5.3)
        w.sets = (w.sets ?? []).map { s in
            var s = s
            s.e1rm_kg = FormulasKit.e1rm(weightKg: s.weight_kg, reps: s.reps, rir: s.rir, isWarmup: s.is_warmup == 1)
            s.updated_at = bump()
            return s
        }
        if let i = workouts.firstIndex(where: { $0.id == w.id }) { workouts[i] = w } else { workouts.append(w) }
        return w
    }
    func deleteWorkout(id: String) async throws -> OkResponse {
        if let i = workouts.firstIndex(where: { $0.id == id }) {
            workouts[i].deleted = 1; workouts[i].updated_at = bump()
            workouts[i].sets = (workouts[i].sets ?? []).map { var s = $0; s.deleted = 1; return s }
        }
        return OkResponse(ok: true)
    }
    func postExercises(_ xs: [ExerciseDTO]) async throws -> UpsertedResponse {
        for x in xs { var x = x; x.updated_at = bump()
            if let i = exercises.firstIndex(where: { $0.id == x.id }) { exercises[i] = x } else { exercises.append(x) } }
        return UpsertedResponse(upserted: xs.count)
    }
    func postBodyMetrics(_ mm: [BodyMetricDTO]) async throws -> UpsertedResponse {
        for m in mm { var m = m; m.updated_at = bump()
            // dedup por (type, ts, source)
            if let i = bodyMetrics.firstIndex(where: { $0.type == m.type && $0.ts == m.ts && $0.source == m.source }) {
                bodyMetrics[i] = m
            } else { bodyMetrics.append(m) } }
        return UpsertedResponse(upserted: mm.count)
    }
    func putDay(date: String, loggingComplete: Bool) async throws -> OkResponse {
        dayFlags[date] = DayFlagDTO(date: date, logging_complete: loggingComplete ? 1 : 0, updated_at: bump())
        return OkResponse(ok: true)
    }
    func putGoals(_ g: [String: String]) async throws -> GoalsResponse {
        for (k, v) in g { goals[k] = v }
        return GoalsResponse(goals: goals)
    }
    func putProgram(startDate: String, json: ProgramJSON) async throws -> ProgramDTO {
        let p = ProgramDTO(id: "prog-\(bump())", start_date: startDate, json: json, active: 1, updated_at: bump(), deleted: 0)
        programDTO = p
        return p
    }

    // MARK: - APIClient (reads)
    func getMeals(from: String, to: String) async throws -> [MealDTO] {
        meals.filter { $0.deleted != 1 && $0.date >= from && $0.date <= to }
    }
    func getWorkouts(from: String, to: String, exerciseId: String?) async throws -> [WorkoutDTO] {
        workouts.filter { w in
            guard w.deleted != 1, w.date >= from, w.date <= to else { return false }
            if let exerciseId { return (w.sets ?? []).contains { $0.exercise_id == exerciseId } }
            return true
        }
    }
    func getExercises() async throws -> [ExerciseDTO] { exercises.filter { $0.deleted != 1 } }
    func getBodyMetrics(type: String, from: String, to: String) async throws -> [BodyMetricDTO] {
        bodyMetrics.filter { $0.deleted != 1 && $0.type == type && $0.date >= from && $0.date <= to }
    }
    func getGoals() async throws -> [String: String] { goals }
    func getProgram() async throws -> ProgramDTO? { programDTO }

    func getSummaryToday(date: String) async throws -> SummaryToday {
        let dayMeals = meals.filter { $0.deleted != 1 && $0.date == date }
        let intake = dayMeals.reduce(Macros.zero) { $0 + Macros(kcal: $1.kcal, protein_g: $1.protein_g, carbs_g: $1.carbs_g, fat_g: $1.fat_g, fiber_g: $1.fiber_g) }
        let weighed = dayMeals.filter { $0.portion_basis == "weighed" }.count
        let low = dayMeals.filter { $0.confidence < 0.7 }.count
        let pct = dayMeals.isEmpty ? 0 : Double(weighed) / Double(dayMeals.count)
        let energy = try await getEnergyStatus()
        let sess = sessionSummary(for: date)
        // §R3: reusar getRecovery (solo sleep_hours + state; no recalcular aparte).
        let rec = try await getRecovery(date: date)
        return SummaryToday(
            date: date,
            intake: .init(kcal: intake.kcal, protein_g: intake.protein_g, carbs_g: intake.carbs_g, fat_g: intake.fat_g, fiber_g: intake.fiber_g),
            targets: .init(kcal: dbl("target_kcal"), protein_g: dbl("target_protein_g"), carbs_g: dbl("target_carbs_g"), fat_g: dbl("target_fat_g")),
            precision: .init(weighed_pct: pct, items: dayMeals.count, low_confidence_items: low),
            weight: .init(trend_kg: energy.weight.trend_kg, delta_7d_kg: delta7d(), last_reading_kg: lastWeight()?.value, last_reading_date: lastWeight()?.date),
            tdee: .init(kcal: energy.tdee.kcal, status: energy.tdee.status),
            session: sess,
            logging_complete: dayFlags[date]?.logging_complete == 1,
            recovery: .init(sleep_hours: rec.sleep.hours, recovery_state: rec.recovery_state))
    }

    // §R2: mismo algoritmo compartido que el fallback local del ViewModel y el backend.
    func getRecovery(date: String) async throws -> Recovery {
        let sn = dbl("sleep_need_hours")
        let needHours = sn > 0 ? sn : FormulasKit.sleepNeedDefaultHours
        return RecoveryCompute.build(date: date, needHours: needHours) { type in
            bodyMetrics.filter { $0.deleted != 1 && $0.type == type && $0.date <= date }
                .sorted { ($0.date, $0.ts) < ($1.date, $1.ts) }
                .map { FormulasKit.DatedValue(date: $0.date, value: $0.value) }
        }
    }

    func getEnergyStatus() async throws -> EnergyStatus {
        let series = weightSeries()
        let windowDays = 21
        let windowStart = cal.date(byAdding: .day, value: -(windowDays - 1), to: Date()) ?? Date()
        let windowStartDay = CBDate.day(windowStart)
        let inWindow = series.filter { $0.date >= windowStartDay }
        let completeInWindow = dayFlags.values.filter { $0.date >= windowStartDay && $0.logging_complete == 1 }
        let weighinsInWindow = bodyMetrics.filter { $0.type == "weight_kg" && $0.date >= windowStartDay }.count
        let deltaEMA = (inWindow.last?.ema_kg ?? 0) - (inWindow.first?.ema_kg ?? 0)
        let completeDays = Set(completeInWindow.map { $0.date })
        let intakeByDay = mealsIntakeByDay()
        let completeIntakes = completeDays.compactMap { intakeByDay[$0] }
        let avgIntake = completeIntakes.isEmpty ? 0 : completeIntakes.reduce(0, +) / Double(completeIntakes.count)
        let trend = series.last?.ema_kg ?? lastWeight()?.value ?? 0
        let tdeeRes = FormulasKit.tdee(
            completeDays: completeDays.count, weighins: weighinsInWindow,
            avgIntakeCompleteDays: avgIntake, deltaEMA: deltaEMA, windowDays: windowDays,
            mifflin: FormulasKit.mifflinStJeor(weightKg: trend, heightCm: dbl("height_cm"), age: Int(dbl("age")), sex: goals["sex"] ?? "m", activityFactor: dbl("activity_factor")))
        let rateActual = deltaEMA / Double(windowDays) * 7.0
        let rateTarget = dbl("goal_rate_kg_per_week")
        let onTrack = abs(rateActual - rateTarget) <= 0.15
        return EnergyStatus(
            tdee: .init(kcal: (tdeeRes.kcal).rounded(), status: tdeeRes.status.rawValue, window_days: windowDays,
                        complete_days_used: completeDays.count, weighins_used: weighinsInWindow),
            weight: .init(trend_kg: (trend * 10).rounded() / 10, trend_series: series, delta_window_kg: (deltaEMA * 100).rounded() / 100),
            intake: .init(avg_kcal_complete_days: avgIntake.rounded(), adherence_pct: adherence()),
            goal: .init(rate_target_kg_per_week: rateTarget, rate_actual_kg_per_week: (rateActual * 100).rounded() / 100, on_track: onTrack),
            recommendation_basis: tdeeRes.status.rawValue)
    }

    func getProgress(exerciseId: String?) async throws -> Progress {
        let weekly = weeklyVolume()
        let prs = recentPRs()
        if let exId = exerciseId {
            let (series, best) = exerciseDetail(exId)
            return Progress(weekly_volume: weekly, prs_recent: prs, e1rm_series: series, best_sets: best)
        }
        return Progress(weekly_volume: weekly, prs_recent: prs, e1rm_series: nil, best_sets: nil)
    }

    func getNextSession(date: String) async throws -> NextSession {
        guard let prog = programDTO?.json,
              let startDate = CBDate.date(fromDay: programDTO?.start_date ?? ""),
              let target = CBDate.date(fromDay: date),
              let dayId = FormulasKit.scheduledDayId(schedule: prog.schedule, startDate: startDate, date: target, calendar: cal),
              dayId != "rest", let day = prog.day(id: dayId) else {
            return NextSession(program_day_id: "rest", name: "Descanso", exercises: [])
        }
        let exs: [NextSession.Exercise] = day.exercises.map { pe in
            let hist = lastSessionSets(exerciseId: pe.exercise_id)
            let inc = exercises.first { $0.id == pe.exercise_id }?.increment_kg ?? 2.5
            let sug = FormulasKit.suggestWeight(lastSessionSets: hist.map {
                FormulasKit.WorkingSet(weightKg: $0.weight_kg, reps: $0.reps, rir: $0.rir, isWarmup: $0.is_warmup == 1)
            }, prescribedSets: pe.sets, repRangeMax: pe.rep_range.last ?? 8, targetRIR: pe.target_rir, incrementKg: inc)
            let last: NextSession.LastSession? = hist.last.map {
                .init(date: lastSessionDate(exerciseId: pe.exercise_id) ?? "",
                      top_set: .init(weight_kg: $0.weight_kg, reps: $0.reps, rir: $0.rir))
            }
            return NextSession.Exercise(
                exercise_id: pe.exercise_id,
                name: exercises.first { $0.id == pe.exercise_id }?.name ?? pe.exercise_id,
                sets: pe.sets, rep_range: pe.rep_range, target_rir: pe.target_rir, rest_sec: pe.rest_sec,
                suggested_weight_kg: sug.weightKg, suggestion_reason: sug.reason.rawValue, last_session: last)
        }
        return NextSession(program_day_id: dayId, name: day.name, exercises: exs)
    }

    func getChanges(since: Int) async throws -> ChangesResponse {
        let allSets = workouts.flatMap { $0.sets ?? [] }
        return ChangesResponse(
            cursor: clock,
            meals: meals.filter { ($0.updated_at ?? 0) > since },
            workouts: workouts.filter { ($0.updated_at ?? 0) > since },
            sets: allSets.filter { ($0.updated_at ?? 0) > since },
            body_metrics: bodyMetrics.filter { ($0.updated_at ?? 0) > since },
            exercises: exercises.filter { ($0.updated_at ?? 0) > since },
            program: [programDTO].compactMap { $0 }.filter { ($0.updated_at ?? 0) > since },
            goals: goals.map { .init(key: $0.key, value: $0.value, updated_at: clock) },
            day_flags: Array(dayFlags.values).filter { ($0.updated_at ?? 0) > since })
    }

    func exportAll() async throws -> Data {
        let dump: [String: Any] = [
            "meals": meals.count, "workouts": workouts.count, "exercises": exercises.count,
            "body_metrics": bodyMetrics.count, "day_flags": dayFlags.count, "goals": goals,
        ]
        return (try? JSONSerialization.data(withJSONObject: dump, options: .prettyPrinted)) ?? Data("{}".utf8)
    }

    // MARK: - Cálculos derivados
    private func dbl(_ k: String) -> Double { Double(goals[k] ?? "") ?? 0 }

    private func weightSeries() -> [EnergyStatus.TrendPointDTO] {
        let readings = bodyMetrics.filter { $0.type == "weight_kg" && $0.deleted != 1 }
            .compactMap { m -> (Date, Double)? in CBDate.date(fromTs: m.ts).map { ($0, m.value) } }
        return FormulasKit.emaSeries(readings: readings, calendar: cal).map {
            .init(date: CBDate.day($0.date), ema_kg: ($0.ema * 100).rounded() / 100)
        }
    }
    private func lastWeight() -> BodyMetricDTO? {
        bodyMetrics.filter { $0.type == "weight_kg" && $0.deleted != 1 }.sorted { $0.ts < $1.ts }.last
    }
    private func delta7d() -> Double? {
        let s = weightSeries(); guard s.count >= 2 else { return nil }
        let last = s.last!.ema_kg
        let idx = max(0, s.count - 8)
        return (last - s[idx].ema_kg * 1.0).rounded(toPlaces: 2)
    }
    private func mealsIntakeByDay() -> [String: Double] {
        var out: [String: Double] = [:]
        for m in meals where m.deleted != 1 { out[m.date, default: 0] += m.kcal }
        return out
    }
    private func adherence() -> Double? {
        let target = dbl("target_kcal"); guard target > 0 else { return nil }
        let byDay = mealsIntakeByDay()
        let completeDays = dayFlags.values.filter { $0.logging_complete == 1 }.map { $0.date }
        guard !completeDays.isEmpty else { return nil }
        let within = completeDays.filter { d in
            guard let k = byDay[d] else { return false }
            return abs(k - target) / target <= 0.05
        }.count
        return Double(within) / Double(completeDays.count)
    }
    private func sessionSummary(for date: String) -> SummaryToday.Session? {
        guard let prog = programDTO?.json, let startDate = CBDate.date(fromDay: programDTO?.start_date ?? ""),
              let target = CBDate.date(fromDay: date),
              let dayId = FormulasKit.scheduledDayId(schedule: prog.schedule, startDate: startDate, date: target, calendar: cal) else { return nil }
        if dayId == "rest" { return .init(program_day_id: "rest", name: "Descanso", exercise_count: 0, completed_today: false) }
        guard let day = prog.day(id: dayId) else { return nil }
        let done = workouts.contains { $0.deleted != 1 && $0.date == date && $0.program_day_id == dayId && $0.ts_end != nil }
        return .init(program_day_id: dayId, name: day.name, exercise_count: day.exercises.count, completed_today: done)
    }
    private func lastSessionSets(exerciseId: String) -> [SetDTO] {
        let sessions = workouts.filter { w in w.deleted != 1 && (w.sets ?? []).contains { $0.exercise_id == exerciseId } }
            .sorted { $0.ts_start < $1.ts_start }
        guard let last = sessions.last else { return [] }
        return (last.sets ?? []).filter { $0.exercise_id == exerciseId && $0.deleted != 1 }.sorted { $0.set_number < $1.set_number }
    }
    private func lastSessionDate(exerciseId: String) -> String? {
        workouts.filter { w in w.deleted != 1 && (w.sets ?? []).contains { $0.exercise_id == exerciseId } }
            .sorted { $0.ts_start < $1.ts_start }.last?.date
    }
    private func weeklyVolume() -> [Progress.WeeklyVolume] {
        var counts: [String: [String: Int]] = [:] // week -> muscle -> sets
        for w in workouts where w.deleted != 1 {
            guard let d = CBDate.date(fromDay: w.date) else { continue }
            let week = isoWeek(d)
            for s in (w.sets ?? []) where s.deleted != 1 && FormulasKit.isEffectiveSet(rir: s.rir, isWarmup: s.is_warmup == 1) {
                let mg = exercises.first { $0.id == s.exercise_id }?.muscle_group ?? "chest"
                counts[week, default: [:]][mg, default: 0] += 1
            }
        }
        var out: [Progress.WeeklyVolume] = []
        for (week, muscles) in counts { for (mg, n) in muscles { out.append(.init(week: week, muscle_group: mg, effective_sets: n)) } }
        return out.sorted { $0.week < $1.week }
    }
    private func recentPRs() -> [Progress.PR] {
        var out: [Progress.PR] = []
        let byExercise = Dictionary(grouping: workouts.filter { $0.deleted != 1 }.flatMap { w in (w.sets ?? []).map { (w, $0) } },
                                    by: { $0.1.exercise_id })
        for (exId, entries) in byExercise {
            let sorted = entries.sorted { $0.0.ts_start < $1.0.ts_start }
            var best = 0.0; var prSet: (WorkoutDTO, SetDTO)?
            for e in sorted { if let v = e.1.e1rm_kg, v > best { best = v; prSet = e } }
            if let pr = prSet, let v = pr.1.e1rm_kg {
                out.append(.init(exercise_id: exId, name: exercises.first { $0.id == exId }?.name ?? exId, e1rm_kg: v, date: pr.0.date))
            }
        }
        return out.sorted { $0.e1rm_kg > $1.e1rm_kg }
    }
    private func exerciseDetail(_ exId: String) -> ([Progress.E1RMPoint], [Progress.BestSet]) {
        var series: [Progress.E1RMPoint] = []
        var best: [Progress.BestSet] = []
        for w in workouts.filter({ $0.deleted != 1 }).sorted(by: { $0.ts_start < $1.ts_start }) {
            let sets = (w.sets ?? []).filter { $0.exercise_id == exId && $0.deleted != 1 }
            let valid = sets.compactMap { $0.e1rm_kg }
            if let top = valid.max() { series.append(.init(date: w.date, e1rm_kg: top)) }
            if let bestSet = sets.max(by: { ($0.e1rm_kg ?? 0) < ($1.e1rm_kg ?? 0) }) {
                best.append(.init(weight_kg: bestSet.weight_kg, reps: bestSet.reps, rir: bestSet.rir, date: w.date))
            }
        }
        return (series, best)
    }
    private func isoWeek(_ d: Date) -> String {
        var c = Calendar(identifier: .iso8601); c.timeZone = CBDate.bogota
        let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
    }
}

private extension Double {
    func rounded(toPlaces p: Int) -> Double { let m = pow(10.0, Double(p)); return (self * m).rounded() / m }
}
