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
    case weightKg = "weight_kg"
    case steps
    case sleepHours = "sleep_hours"
    case restingHr = "resting_hr"
    case activeKcal = "active_kcal"
}

enum MetricSource: String, Codable {
    case healthkit, manual
}
