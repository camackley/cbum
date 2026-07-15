import Foundation

// DTOs Codable 1:1 con contracts §3/§4. Nombres de campo EXACTOS a las claves
// JSON (snake_case) para un mapeo sin ambigüedad — nada de estrategias de
// conversión que puedan sorprender. Optionals para campos de solo-lectura.

// MARK: - §4 Program JSON

struct ProgramExercise: Codable, Equatable {
    var exercise_id: String
    var sets: Int
    var rep_range: [Int]        // [min, max]
    var target_rir: Int
    var rest_sec: Int
    var notes: String?
}

struct ProgramDay: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var exercises: [ProgramExercise]
}

struct ProgramJSON: Codable, Equatable {
    var version: Int
    var name: String
    var days: [ProgramDay]
    var schedule: [String]

    func day(id: String) -> ProgramDay? { days.first { $0.id == id } }
}

// Decodifica un valor que puede llegar como objeto JSON, como string JSON (una
// columna TEXT de D1 como `per_100g`) o como null — así un solo campo mal
// serializado por el backend no rompe todo el pull de /api/changes.
struct JSONText<T: Codable>: Codable {
    var value: T?
    init(_ value: T?) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil; return }
        if let obj = try? c.decode(T.self) { value = obj; return }
        if let str = try? c.decode(String.self), let data = str.data(using: .utf8) {
            value = try? JSONDecoder().decode(T.self, from: data); return
        }
        value = nil
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let value { try c.encode(value) } else { try c.encodeNil() }
    }
}

// MARK: - Entity DTOs

struct MealDTO: Codable, Identifiable {
    var id: String
    var ts: String
    var date: String
    var meal_group_id: String
    var name: String
    var quantity_g: Double?
    var kcal: Double
    var protein_g: Double
    var carbs_g: Double
    var fat_g: Double
    var fiber_g: Double?
    var per_100g: JSONText<Macros>?     // objeto JSON, string JSON (columna TEXT), o null
    var source: String
    var confidence: Double
    var portion_basis: String
    var fdc_id: Int?
    var off_id: String?
    var notes: String?
    var updated_at: Int?
    var deleted: Int?
}

struct ExerciseDTO: Codable, Identifiable {
    var id: String
    var name: String
    var muscle_group: String
    var pattern: String
    var equipment: String
    var increment_kg: Double
    var updated_at: Int?
    var deleted: Int?
}

struct SetDTO: Codable, Identifiable {
    var id: String
    var workout_id: String
    var exercise_id: String
    var set_number: Int
    var weight_kg: Double
    var reps: Int
    var rir: Int
    var is_warmup: Int
    var e1rm_kg: Double?
    var updated_at: Int?
    var deleted: Int?
}

struct WorkoutDTO: Codable, Identifiable {
    var id: String
    var ts_start: String
    var ts_end: String?
    var date: String
    var program_day_id: String?
    var notes: String?
    var sets: [SetDTO]?
    var updated_at: Int?
    var deleted: Int?
}

struct BodyMetricDTO: Codable, Identifiable {
    var id: String
    var ts: String
    var date: String
    var type: String
    var value: Double
    var source: String
    var updated_at: Int?
    var deleted: Int?
}

struct DayFlagDTO: Codable {
    var date: String
    var logging_complete: Int
    var updated_at: Int?
}

struct ProgramDTO: Codable {
    var id: String
    var start_date: String
    var json: ProgramJSON
    var active: Int?
    var updated_at: Int?
    var deleted: Int?
}

// MARK: - Request wrappers

struct MealsRequest: Codable { var meals: [MealDTO] }
struct ExercisesRequest: Codable { var exercises: [ExerciseDTO] }
struct BodyMetricsRequest: Codable { var metrics: [BodyMetricDTO] }
struct WorkoutRequest: Codable { var workout: WorkoutDTO }
struct DayUpdateRequest: Codable { var logging_complete: Bool }
struct GoalsRequest: Codable { var goals: [String: String] }
struct ProgramUpdateRequest: Codable { var start_date: String; var json: ProgramJSON }
struct UpsertedResponse: Codable { var upserted: Int }
struct OkResponse: Codable { var ok: Bool }
struct HealthResponse: Codable { var ok: Bool; var version: String }

struct MealsResponse: Codable { var meals: [MealDTO] }
struct WorkoutsResponse: Codable { var workouts: [WorkoutDTO] }
struct ExercisesResponse: Codable { var exercises: [ExerciseDTO] }
struct BodyMetricsResponse: Codable { var metrics: [BodyMetricDTO] }
struct GoalsResponse: Codable { var goals: [String: String] }
struct ProgramResponse: Codable { var program: ProgramDTO? }
struct WorkoutResponse: Codable { var workout: WorkoutDTO? }

// MARK: - §3.1 summary/today

struct SummaryToday: Codable {
    struct Intake: Codable { var kcal: Double; var protein_g: Double; var carbs_g: Double; var fat_g: Double; var fiber_g: Double? }
    struct Targets: Codable { var kcal: Double; var protein_g: Double; var carbs_g: Double; var fat_g: Double }
    struct Precision: Codable { var weighed_pct: Double; var items: Int; var low_confidence_items: Int }
    struct Weight: Codable { var trend_kg: Double?; var delta_7d_kg: Double?; var last_reading_kg: Double?; var last_reading_date: String? }
    struct TDEE: Codable { var kcal: Double; var status: String }
    struct Session: Codable { var program_day_id: String; var name: String; var exercise_count: Int; var completed_today: Bool }
    var date: String
    var intake: Intake
    var targets: Targets
    var precision: Precision
    var weight: Weight
    var tdee: TDEE
    var session: Session?
    var logging_complete: Bool
}

// MARK: - §3.2 energy-status

struct EnergyStatus: Codable {
    struct TDEE: Codable { var kcal: Double; var status: String; var window_days: Int; var complete_days_used: Int; var weighins_used: Int }
    struct TrendPointDTO: Codable { var date: String; var ema_kg: Double }
    struct Weight: Codable { var trend_kg: Double?; var trend_series: [TrendPointDTO]; var delta_window_kg: Double? }
    struct Intake: Codable { var avg_kcal_complete_days: Double?; var adherence_pct: Double? }
    struct Goal: Codable { var rate_target_kg_per_week: Double?; var rate_actual_kg_per_week: Double?; var on_track: Bool? }
    var tdee: TDEE
    var weight: Weight
    var intake: Intake
    var goal: Goal
    var recommendation_basis: String
}

// MARK: - §3.3 progress

struct Progress: Codable {
    struct WeeklyVolume: Codable { var week: String; var muscle_group: String; var effective_sets: Int }
    struct PR: Codable { var exercise_id: String; var name: String; var e1rm_kg: Double; var date: String }
    struct E1RMPoint: Codable { var date: String; var e1rm_kg: Double }
    struct BestSet: Codable { var weight_kg: Double; var reps: Int; var rir: Int; var date: String }
    var weekly_volume: [WeeklyVolume]
    var prs_recent: [PR]
    var e1rm_series: [E1RMPoint]?
    var best_sets: [BestSet]?
}

// MARK: - §3.4 next-session

struct NextSession: Codable {
    struct TopSet: Codable { var weight_kg: Double; var reps: Int; var rir: Int }
    struct LastSession: Codable { var date: String; var top_set: TopSet }
    struct Exercise: Codable, Identifiable {
        var exercise_id: String
        var name: String
        var sets: Int
        var rep_range: [Int]
        var target_rir: Int
        var rest_sec: Int
        var suggested_weight_kg: Double?
        var suggestion_reason: String
        var last_session: LastSession?
        var id: String { exercise_id }
    }
    var program_day_id: String
    var name: String
    var exercises: [Exercise]
}

// MARK: - §3 changes feed

struct ChangesResponse: Codable {
    var cursor: Int
    var meals: [MealDTO]
    var workouts: [WorkoutDTO]
    var sets: [SetDTO]
    var body_metrics: [BodyMetricDTO]
    var exercises: [ExerciseDTO]
    var program: [ProgramDTO]
    var goals: [GoalKV]
    var day_flags: [DayFlagDTO]

    struct GoalKV: Codable { var key: String; var value: String; var updated_at: Int? }
}
