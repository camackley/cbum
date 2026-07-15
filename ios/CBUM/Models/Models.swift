import Foundation
import SwiftData

// @Model espejo de las tablas de contracts §1. Campos idénticos (ids String uuid,
// fechas String como el server las maneja + helpers a Date). Los campos con CHECK
// se guardan como String raw + accessor de enum (evita edge-cases de SwiftData).
//
// Convención de sync: `updatedAt` (epoch ms) lo pone el server; local puede ser 0
// hasta el primer pull. `deleted` soft-delete. `dirty` marca pendiente de outbox.
// `syncError` guarda un 422 no reintentable para mostrar en Ajustes.

@Model
final class Meal {
    @Attribute(.unique) var id: String
    var ts: String              // ISO-8601 con offset
    var date: String            // YYYY-MM-DD (Bogotá)
    var mealGroupId: String
    var name: String
    var quantityG: Double?
    var kcal: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double?
    var per100gJSON: String?    // JSON {kcal,protein_g,...}
    var sourceRaw: String
    var confidence: Double
    var portionBasisRaw: String
    var fdcId: Int?
    var offId: String?
    var notes: String?
    var updatedAt: Int
    var deleted: Bool
    var dirty: Bool
    var syncError: String?

    var source: MealSource { MealSource(rawValue: sourceRaw) ?? .manual }
    var portionBasis: PortionBasis { PortionBasis(rawValue: portionBasisRaw) ?? .estimated }
    var per100g: Macros? {
        get {
            guard let per100gJSON, let data = per100gJSON.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Macros.self, from: data)
        }
        set {
            per100gJSON = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) ?? nil }
        }
    }
    var macros: Macros { Macros(kcal: kcal, protein_g: proteinG, carbs_g: carbsG, fat_g: fatG, fiber_g: fiberG) }

    init(id: String = UUID().uuidString, ts: String, date: String, mealGroupId: String,
         name: String, quantityG: Double?, kcal: Double, proteinG: Double, carbsG: Double,
         fatG: Double, fiberG: Double?, per100gJSON: String? = nil, source: MealSource,
         confidence: Double, portionBasis: PortionBasis, fdcId: Int? = nil, offId: String? = nil,
         notes: String? = nil, updatedAt: Int = 0, deleted: Bool = false, dirty: Bool = true) {
        self.id = id; self.ts = ts; self.date = date; self.mealGroupId = mealGroupId
        self.name = name; self.quantityG = quantityG; self.kcal = kcal; self.proteinG = proteinG
        self.carbsG = carbsG; self.fatG = fatG; self.fiberG = fiberG; self.per100gJSON = per100gJSON
        self.sourceRaw = source.rawValue; self.confidence = confidence
        self.portionBasisRaw = portionBasis.rawValue; self.fdcId = fdcId; self.offId = offId
        self.notes = notes; self.updatedAt = updatedAt; self.deleted = deleted; self.dirty = dirty
    }
}

@Model
final class Exercise {
    @Attribute(.unique) var id: String   // slug estable
    var name: String
    var muscleGroupRaw: String
    var patternRaw: String
    var equipmentRaw: String
    var incrementKg: Double
    var updatedAt: Int
    var deleted: Bool

    var muscleGroup: MuscleGroup { MuscleGroup(rawValue: muscleGroupRaw) ?? .chest }
    var pattern: MovementPattern { MovementPattern(rawValue: patternRaw) ?? .isolation }
    var equipment: Equipment { Equipment(rawValue: equipmentRaw) ?? .barbell }

    init(id: String, name: String, muscleGroup: MuscleGroup, pattern: MovementPattern,
         equipment: Equipment, incrementKg: Double, updatedAt: Int = 0, deleted: Bool = false) {
        self.id = id; self.name = name; self.muscleGroupRaw = muscleGroup.rawValue
        self.patternRaw = pattern.rawValue; self.equipmentRaw = equipment.rawValue
        self.incrementKg = incrementKg; self.updatedAt = updatedAt; self.deleted = deleted
    }
}

@Model
final class Workout {
    @Attribute(.unique) var id: String
    var tsStart: String
    var tsEnd: String?
    var date: String
    var programDayId: String?
    var notes: String?
    var updatedAt: Int
    var deleted: Bool
    var dirty: Bool
    var finished: Bool     // local: máquina de estados (ts_end seteado + posteado)
    var syncError: String? // 422 no reintentable (se muestra en Ajustes)

    init(id: String = UUID().uuidString, tsStart: String, tsEnd: String? = nil, date: String,
         programDayId: String? = nil, notes: String? = nil, updatedAt: Int = 0,
         deleted: Bool = false, dirty: Bool = true, finished: Bool = false, syncError: String? = nil) {
        self.id = id; self.tsStart = tsStart; self.tsEnd = tsEnd; self.date = date
        self.programDayId = programDayId; self.notes = notes; self.updatedAt = updatedAt
        self.deleted = deleted; self.dirty = dirty; self.finished = finished; self.syncError = syncError
    }
}

@Model
final class WorkoutSet {
    @Attribute(.unique) var id: String
    var workoutId: String
    var exerciseId: String
    var setNumber: Int
    var weightKg: Double
    var reps: Int
    var rir: Int
    var isWarmup: Bool
    var e1rmKg: Double?     // calculado local con FormulasKit (misma fórmula que server §5.3)
    var updatedAt: Int
    var deleted: Bool
    var dirty: Bool

    init(id: String = UUID().uuidString, workoutId: String, exerciseId: String, setNumber: Int,
         weightKg: Double, reps: Int, rir: Int, isWarmup: Bool = false, e1rmKg: Double? = nil,
         updatedAt: Int = 0, deleted: Bool = false, dirty: Bool = true) {
        self.id = id; self.workoutId = workoutId; self.exerciseId = exerciseId
        self.setNumber = setNumber; self.weightKg = weightKg; self.reps = reps; self.rir = rir
        self.isWarmup = isWarmup; self.e1rmKg = e1rmKg; self.updatedAt = updatedAt
        self.deleted = deleted; self.dirty = dirty
    }
}

@Model
final class BodyMetric {
    @Attribute(.unique) var id: String
    var ts: String
    var date: String
    var typeRaw: String
    var value: Double
    var sourceRaw: String
    var updatedAt: Int
    var deleted: Bool
    var dirty: Bool

    var type: BodyMetricType { BodyMetricType(rawValue: typeRaw) ?? .weightKg }
    var source: MetricSource { MetricSource(rawValue: sourceRaw) ?? .manual }

    init(id: String = UUID().uuidString, ts: String, date: String, type: BodyMetricType,
         value: Double, source: MetricSource, updatedAt: Int = 0, deleted: Bool = false, dirty: Bool = true) {
        self.id = id; self.ts = ts; self.date = date; self.typeRaw = type.rawValue
        self.value = value; self.sourceRaw = source.rawValue; self.updatedAt = updatedAt
        self.deleted = deleted; self.dirty = dirty
    }
}

@Model
final class DayFlag {
    @Attribute(.unique) var date: String   // PRIMARY KEY
    var loggingComplete: Bool
    var updatedAt: Int
    var dirty: Bool

    init(date: String, loggingComplete: Bool, updatedAt: Int = 0, dirty: Bool = true) {
        self.date = date; self.loggingComplete = loggingComplete
        self.updatedAt = updatedAt; self.dirty = dirty
    }
}

@Model
final class ProgramModel {
    @Attribute(.unique) var id: String
    var active: Bool
    var startDate: String
    var json: String       // schema §4
    var updatedAt: Int
    var deleted: Bool

    var program: ProgramJSON? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProgramJSON.self, from: data)
    }

    init(id: String, active: Bool, startDate: String, json: String, updatedAt: Int = 0, deleted: Bool = false) {
        self.id = id; self.active = active; self.startDate = startDate; self.json = json
        self.updatedAt = updatedAt; self.deleted = deleted
    }
}

@Model
final class Goal {
    @Attribute(.unique) var key: String
    var value: String
    var updatedAt: Int
    var dirty: Bool

    init(key: String, value: String, updatedAt: Int = 0, dirty: Bool = true) {
        self.key = key; self.value = value; self.updatedAt = updatedAt; self.dirty = dirty
    }
}

// Outbox: cola FIFO de writes para el SyncEngine (offline-first, idempotente).
@Model
final class OutboxItem {
    @Attribute(.unique) var id: String
    var createdAt: Int        // epoch ms local (orden FIFO)
    var endpoint: String      // ej. "/api/meals"
    var method: String        // POST/PATCH/PUT/DELETE
    var bodyJSON: String      // payload serializado
    var attempts: Int
    var lastError: String?

    init(id: String = UUID().uuidString, createdAt: Int, endpoint: String, method: String,
         bodyJSON: String, attempts: Int = 0, lastError: String? = nil) {
        self.id = id; self.createdAt = createdAt; self.endpoint = endpoint; self.method = method
        self.bodyJSON = bodyJSON; self.attempts = attempts; self.lastError = lastError
    }
}
