import Foundation

// Errores tipados del API (I2).
enum APIError: Error, LocalizedError {
    case unauthorized
    case validation(String)      // 422 — NO reintentar
    case network(String)
    case server(Int, String)
    case notConfigured
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "No autorizado — revisa el API token en Ajustes."
        case .validation(let m): return "Validación: \(m)"
        case .network(let m): return "Red: \(m)"
        case .server(let c, let m): return "Servidor (\(c)): \(m)"
        case .notConfigured: return "Backend no configurado (base URL / token)."
        case .decoding(let m): return "Decodificación: \(m)"
        }
    }
    /// Errores de red se reintentan; 422/401 no.
    var isRetryable: Bool {
        switch self {
        case .network, .server: return true
        case .unauthorized, .validation, .notConfigured, .decoding: return false
        }
    }
}

struct APIErrorBody: Codable { struct E: Codable { var code: String; var message: String }; var error: E }

// Contrato del API client — intercambiable (Live vs Mock) por configuración.
protocol APIClient {
    func health() async throws -> HealthResponse
    // Escrituras (upserts idempotentes por id)
    func postMeals(_ meals: [MealDTO]) async throws -> UpsertedResponse
    func patchMeal(id: String, fields: [String: Any]) async throws -> MealDTO
    func deleteMeal(id: String) async throws -> OkResponse
    func postWorkout(_ workout: WorkoutDTO) async throws -> WorkoutDTO
    func deleteWorkout(id: String) async throws -> OkResponse
    func postExercises(_ exercises: [ExerciseDTO]) async throws -> UpsertedResponse
    func postBodyMetrics(_ metrics: [BodyMetricDTO]) async throws -> UpsertedResponse
    func putDay(date: String, loggingComplete: Bool) async throws -> OkResponse
    func putGoals(_ goals: [String: String]) async throws -> GoalsResponse
    func putProgram(startDate: String, json: ProgramJSON) async throws -> ProgramDTO
    // Lecturas
    func getMeals(from: String, to: String) async throws -> [MealDTO]
    func getWorkouts(from: String, to: String, exerciseId: String?) async throws -> [WorkoutDTO]
    func getExercises() async throws -> [ExerciseDTO]
    func getBodyMetrics(type: String, from: String, to: String) async throws -> [BodyMetricDTO]
    func getGoals() async throws -> [String: String]
    func getProgram() async throws -> ProgramDTO?
    func getSummaryToday(date: String) async throws -> SummaryToday
    func getRecovery(date: String) async throws -> Recovery
    func getEnergyStatus() async throws -> EnergyStatus
    func getProgress(exerciseId: String?) async throws -> Progress
    func getNextSession(date: String) async throws -> NextSession
    func getChanges(since: Int) async throws -> ChangesResponse
    func exportAll() async throws -> Data
}

// MARK: - Live implementation

final class LiveAPIClient: APIClient {
    private let config: AppConfig
    private let session: URLSession

    init(config: AppConfig = .shared, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    private var encoder: JSONEncoder { JSONEncoder() }
    private var decoder: JSONDecoder { JSONDecoder() }

    private func request(_ method: String, _ path: String,
                         query: [String: String] = [:], body: Data? = nil) async throws -> Data {
        guard !config.baseURL.isEmpty, !config.apiToken.isEmpty else { throw APIError.notConfigured }
        guard var comps = URLComponents(string: config.baseURL + path) else { throw APIError.network("URL inválida") }
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps.url else { throw APIError.network("URL inválida") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(config.apiToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.network("Sin respuesta HTTP") }
            switch http.statusCode {
            case 200...299: return data
            case 401: throw APIError.unauthorized
            case 422:
                let msg = (try? decoder.decode(APIErrorBody.self, from: data))?.error.message ?? "422"
                throw APIError.validation(msg)
            default:
                let msg = (try? decoder.decode(APIErrorBody.self, from: data))?.error.message ?? "HTTP \(http.statusCode)"
                throw APIError.server(http.statusCode, msg)
            }
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
    }

    func health() async throws -> HealthResponse {
        try decode(HealthResponse.self, await request("GET", "/api/health"))
    }
    func postMeals(_ meals: [MealDTO]) async throws -> UpsertedResponse {
        let body = try encoder.encode(MealsRequest(meals: meals))
        return try decode(UpsertedResponse.self, await request("POST", "/api/meals", body: body))
    }
    func patchMeal(id: String, fields: [String: Any]) async throws -> MealDTO {
        let body = try JSONSerialization.data(withJSONObject: fields)
        return try decode(MealDTO.self, await request("PATCH", "/api/meals/\(id)", body: body))
    }
    func deleteMeal(id: String) async throws -> OkResponse {
        try decode(OkResponse.self, await request("DELETE", "/api/meals/\(id)"))
    }
    func postWorkout(_ workout: WorkoutDTO) async throws -> WorkoutDTO {
        let body = try encoder.encode(WorkoutRequest(workout: workout))
        let data = try await request("POST", "/api/workouts", body: body)
        // El server puede responder el workout directo o envuelto.
        if let w = try? decoder.decode(WorkoutDTO.self, from: data) { return w }
        return try decode(WorkoutResponse.self, data).workout ?? workout
    }
    func deleteWorkout(id: String) async throws -> OkResponse {
        try decode(OkResponse.self, await request("DELETE", "/api/workouts/\(id)"))
    }
    func postExercises(_ exercises: [ExerciseDTO]) async throws -> UpsertedResponse {
        let body = try encoder.encode(ExercisesRequest(exercises: exercises))
        return try decode(UpsertedResponse.self, await request("POST", "/api/exercises", body: body))
    }
    func postBodyMetrics(_ metrics: [BodyMetricDTO]) async throws -> UpsertedResponse {
        let body = try encoder.encode(BodyMetricsRequest(metrics: metrics))
        return try decode(UpsertedResponse.self, await request("POST", "/api/body-metrics", body: body))
    }
    func putDay(date: String, loggingComplete: Bool) async throws -> OkResponse {
        let body = try encoder.encode(DayUpdateRequest(logging_complete: loggingComplete))
        return try decode(OkResponse.self, await request("PUT", "/api/days/\(date)", body: body))
    }
    func putGoals(_ goals: [String: String]) async throws -> GoalsResponse {
        let body = try encoder.encode(GoalsRequest(goals: goals))
        return try decode(GoalsResponse.self, await request("PUT", "/api/goals", body: body))
    }
    func putProgram(startDate: String, json: ProgramJSON) async throws -> ProgramDTO {
        let body = try encoder.encode(ProgramUpdateRequest(start_date: startDate, json: json))
        let data = try await request("PUT", "/api/program", body: body)
        if let p = try? decoder.decode(ProgramResponse.self, from: data), let prog = p.program { return prog }
        return try decode(ProgramDTO.self, data)
    }
    func getMeals(from: String, to: String) async throws -> [MealDTO] {
        try decode(MealsResponse.self, await request("GET", "/api/meals", query: ["from": from, "to": to])).meals
    }
    func getWorkouts(from: String, to: String, exerciseId: String?) async throws -> [WorkoutDTO] {
        var q = ["from": from, "to": to]; if let exerciseId { q["exercise_id"] = exerciseId }
        return try decode(WorkoutsResponse.self, await request("GET", "/api/workouts", query: q)).workouts
    }
    func getExercises() async throws -> [ExerciseDTO] {
        try decode(ExercisesResponse.self, await request("GET", "/api/exercises")).exercises
    }
    func getBodyMetrics(type: String, from: String, to: String) async throws -> [BodyMetricDTO] {
        try decode(BodyMetricsResponse.self, await request("GET", "/api/body-metrics",
            query: ["type": type, "from": from, "to": to])).metrics
    }
    func getGoals() async throws -> [String: String] {
        try decode(GoalsResponse.self, await request("GET", "/api/goals")).goals
    }
    func getProgram() async throws -> ProgramDTO? {
        try decode(ProgramResponse.self, await request("GET", "/api/program")).program
    }
    func getSummaryToday(date: String) async throws -> SummaryToday {
        try decode(SummaryToday.self, await request("GET", "/api/summary/today", query: ["date": date]))
    }
    func getRecovery(date: String) async throws -> Recovery {
        try decode(Recovery.self, await request("GET", "/api/recovery", query: ["date": date]))
    }
    func getEnergyStatus() async throws -> EnergyStatus {
        try decode(EnergyStatus.self, await request("GET", "/api/energy-status"))
    }
    func getProgress(exerciseId: String?) async throws -> Progress {
        var q: [String: String] = [:]; if let exerciseId { q["exercise_id"] = exerciseId }
        return try decode(Progress.self, await request("GET", "/api/progress", query: q))
    }
    func getNextSession(date: String) async throws -> NextSession {
        try decode(NextSession.self, await request("GET", "/api/next-session", query: ["date": date]))
    }
    func getChanges(since: Int) async throws -> ChangesResponse {
        try decode(ChangesResponse.self, await request("GET", "/api/changes", query: ["since": String(since)]))
    }
    func exportAll() async throws -> Data {
        try await request("GET", "/api/export")
    }
}
