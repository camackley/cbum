import SwiftUI

// Router de navegación entre tabs. Permite que HOY mande a la Sesión y que la
// Sesión en curso muestre una pill para volver.
@MainActor
@Observable
final class Router {
    var tab: CBTab = .hoy
    var autostartSession = false     // HOY pidió empezar el entreno del día
    var startFreeWorkout = false     // "Entreno libre"

    func goToSession(autostart: Bool = false, free: Bool = false) {
        autostartSession = autostart
        startFreeWorkout = free
        tab = .entreno
    }
}
