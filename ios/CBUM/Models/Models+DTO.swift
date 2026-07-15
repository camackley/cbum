import Foundation

// Conversión @Model → DTO para escribir por el outbox (contracts §3).
// Los POST no llevan updated_at/deleted (los pone el server) → se dejan nil.

extension Meal {
    func toDTO() -> MealDTO {
        MealDTO(id: id, ts: ts, date: date, meal_group_id: mealGroupId, name: name,
                quantity_g: quantityG, kcal: kcal, protein_g: proteinG, carbs_g: carbsG,
                fat_g: fatG, fiber_g: fiberG, per_100g: per100g.map { JSONText($0) }, source: sourceRaw,
                confidence: confidence, portion_basis: portionBasisRaw, fdc_id: fdcId,
                off_id: offId, notes: notes, updated_at: nil, deleted: nil)
    }
}

extension WorkoutSet {
    func toDTO() -> SetDTO {
        SetDTO(id: id, workout_id: workoutId, exercise_id: exerciseId, set_number: setNumber,
               weight_kg: weightKg, reps: reps, rir: rir, is_warmup: isWarmup ? 1 : 0,
               e1rm_kg: e1rmKg, updated_at: nil, deleted: nil)
    }
}

extension Workout {
    func toDTO(sets: [SetDTO]) -> WorkoutDTO {
        WorkoutDTO(id: id, ts_start: tsStart, ts_end: tsEnd, date: date,
                   program_day_id: programDayId, notes: notes, sets: sets, updated_at: nil, deleted: nil)
    }
}

extension Exercise {
    func toDTO() -> ExerciseDTO {
        ExerciseDTO(id: id, name: name, muscle_group: muscleGroupRaw, pattern: patternRaw,
                    equipment: equipmentRaw, increment_kg: incrementKg, updated_at: nil, deleted: nil)
    }
}

extension BodyMetric {
    func toDTO() -> BodyMetricDTO {
        BodyMetricDTO(id: id, ts: ts, date: date, type: typeRaw, value: value,
                      source: sourceRaw, updated_at: nil, deleted: nil)
    }
}
