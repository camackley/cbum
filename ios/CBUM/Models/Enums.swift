import Foundation

// Enums Swift con rawValues EXACTOS a los CHECK de SQL en contracts §1.

enum MealSource: String, Codable, CaseIterable {
    case label, barcode, photo, manual
}

enum PortionBasis: String, Codable, CaseIterable {
    case weighed, estimated
}

enum MuscleGroup: String, Codable, CaseIterable {
    case chest, back, shoulders, biceps, triceps
    case quads, hamstrings, glutes, calves, abs

    var displayName: String {
        switch self {
        case .chest: return "Pecho"
        case .back: return "Espalda"
        case .shoulders: return "Hombros"
        case .biceps: return "Bíceps"
        case .triceps: return "Tríceps"
        case .quads: return "Cuádriceps"
        case .hamstrings: return "Isquios"
        case .glutes: return "Glúteos"
        case .calves: return "Gemelos"
        case .abs: return "Abdomen"
        }
    }
}

enum MovementPattern: String, Codable, CaseIterable {
    case horizontalPush = "horizontal_push"
    case verticalPush = "vertical_push"
    case horizontalPull = "horizontal_pull"
    case verticalPull = "vertical_pull"
    case squat, hinge, lunge, isolation, carry, core
}

enum Equipment: String, Codable, CaseIterable {
    case barbell, dumbbell, machine, cable, bodyweight, smith
}

enum BodyMetricType: String, Codable, CaseIterable {
    // V1
    case weightKg = "weight_kg"
    case steps
    case sleepHours = "sleep_hours"
    case restingHr = "resting_hr"
    case activeKcal = "active_kcal"
    // V2 vitales (delta §R1)
    case hrvMs = "hrv_ms"
    case respiratoryRate = "respiratory_rate"
    // V2 fases de sueño / eficiencia / consistencia
    case sleepDeepHours = "sleep_deep_hours"
    case sleepRemHours = "sleep_rem_hours"
    case sleepCoreHours = "sleep_core_hours"
    case sleepAwakeHours = "sleep_awake_hours"
    case sleepInbedHours = "sleep_inbed_hours"
    case sleepMidpointHour = "sleep_midpoint_hour"
    // V2 composición (báscula)
    case bodyFatPct = "body_fat_pct"
    case leanMassKg = "lean_mass_kg"
}

enum MetricSource: String, Codable {
    case healthkit, manual
}
