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
