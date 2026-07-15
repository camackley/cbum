import Foundation
#if canImport(UIKit)
import UIKit
import AudioToolbox
#endif

// Feedback háptico + sonido corto (rest timer, PR). Sin dependencias.
enum Haptics {
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    static func timerDone() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        AudioServicesPlaySystemSound(1005)   // sonido corto del sistema
        #endif
    }
}
