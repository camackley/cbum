import SwiftUI
import SwiftData

@main
struct CBUMApp: App {
    @State private var env = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .modelContainer(env.container)
                .preferredColorScheme(.dark)   // dark mode forzado
                .tint(CB.bone)
                .task {
                    env.recoverUnfinishedWorkouts()  // rescata sesiones huérfanas
                    await env.sync.syncNow()          // trigger: launch
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { env.syncNow() }    // trigger: foreground
        }
    }
}
