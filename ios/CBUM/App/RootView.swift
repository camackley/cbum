import SwiftUI

// Shell de navegación: contenido por tab + CBTabBar inferior. Las 5 pantallas
// reales viven en Features/. El Router coordina la navegación entre tabs.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var router = Router()

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            CBTabBar(active: $router.tab)
        }
        .background(CB.bgApp.ignoresSafeArea())
        .environment(router)
        .onAppear(perform: applyScreenshotHook)
    }

    // Hook de navegación para capturas deterministas (CBUM_SCREEN). Sin efecto en
    // uso normal (variable ausente). Los rangos de chart se fijan por launch-args
    // que iOS mapea a UserDefaults (-cbum.chartRange.<id> <valor>).
    private func applyScreenshotHook() {
        switch ProcessInfo.processInfo.environment["CBUM_SCREEN"] {
        case "recovery": router.goToProgress("recuperacion")
        case "body": router.goToProgress("cuerpo")
        case "strength": router.goToProgress("fuerza")
        case "settings": router.tab = .ajustes
        default: break
        }
    }

    @ViewBuilder
    private var content: some View {
        switch router.tab {
        case .hoy: TodayView()
        case .entreno: SessionView()
        case .nutricion: NutritionView()
        case .progreso: ProgressScreen()
        case .ajustes: SettingsView()
        }
    }
}
