import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// Pantalla AJUSTES (spec I4): Objetivos, Conexión, HealthKit, Data, Programa, versión.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showGallery = false
    @State private var showGoals = false
    @State private var showProgram = false
    @State private var exportFile: ExportFile?

    // Conexión (local, se persisten al guardar)
    @State private var baseURL = ""
    @State private var token = ""
    @State private var useMock = true
    @State private var healthGranted = false
    @State private var testResult: String?

    var body: some View {
        VStack(spacing: 0) {
            CBHeader(title: "Ajustes")
            ScrollView {
                VStack(alignment: .leading, spacing: CBSpace.s6) {
                    goalsSection
                    connectionSection
                    healthKitSection
                    dataSection
                    programSection
                    aboutSection
                }
                .padding(CBSpace.gutterScreen)
                .padding(.bottom, CBSpace.s10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CB.bgApp)
        .onAppear {
            baseURL = env.config.baseURL
            token = env.config.apiToken
            useMock = env.config.useMockAPI
            healthGranted = env.health.writeAuthorized()
        }
        .sheet(isPresented: $showGallery) { ComponentGallery() }
        .sheet(isPresented: $showGoals) { GoalsForm() }
        .sheet(isPresented: $showProgram) { ProgramView() }
        .sheet(item: $exportFile) { file in ActivityView(url: file.url) }
    }

    // MARK: Objetivos
    private var goalsSection: some View {
        section("Objetivos") {
            row("Metas de macros, peso y ritmo") { showGoals = true }
            Text("El coach puede cambiar esto por ti.").font(CBFont.caption).foregroundStyle(CB.textTertiary)
        }
    }

    // MARK: Conexión
    private var connectionSection: some View {
        section("Conexión") {
            VStack(alignment: .leading, spacing: CBSpace.s3) {
                Toggle(isOn: Binding(get: { useMock }, set: { useMock = $0; env.switchClient(useMock: $0) })) {
                    Text("Usar mock local").font(CBFont.body).foregroundStyle(CB.textPrimary)
                }.tint(CB.bone)

                field("Base URL", text: $baseURL, placeholder: "https://…workers.dev")
                secureField("API Token", text: $token)

                HStack(spacing: CBSpace.s3) {
                    CBButton(title: "Guardar", style: .secondary, size: .sm, fullWidth: false) {
                        env.config.baseURL = baseURL; env.config.apiToken = token
                        env.switchClient(useMock: useMock)
                    }
                    CBButton(title: "Probar conexión", style: .secondary, size: .sm, fullWidth: false) {
                        Task { await testConnection() }
                    }
                }
                if let testResult { Text(testResult).font(CBFont.caption).foregroundStyle(testResult.hasPrefix("OK") ? CB.success : CB.alert) }

                Divider().overlay(CB.borderDefault)
                syncStatus
            }
        }
    }

    private var syncStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Pendientes en outbox").font(CBFont.bodySM).foregroundStyle(CB.textSecondary)
                Spacer()
                Text("\(env.sync.pendingCount)").cbNumber(18, color: env.sync.pendingCount > 0 ? CB.estimated : CB.success)
            }
            HStack {
                Text("Último sync").font(CBFont.bodySM).foregroundStyle(CB.textSecondary)
                Spacer()
                Text(env.config.lastSyncAt.map { CBDate.hour(fromTs: CBDate.ts($0)) } ?? "—")
                    .font(CBFont.mono(12)).foregroundStyle(CB.textTertiary)
            }
            if let e = env.sync.lastError {
                Text(e).font(CBFont.caption).foregroundStyle(CB.alert)
            }
            if syncErrorCount > 0 {
                Text("\(syncErrorCount) registros con error 422 (revisa datos)").font(CBFont.caption).foregroundStyle(CB.alert)
            }
            CBButton(title: "Sincronizar ahora", style: .secondary, size: .sm, fullWidth: false) { env.syncNow() }
        }
    }

    private var syncErrorCount: Int {
        let meals = ((try? env.context.fetch(FetchDescriptor<Meal>(predicate: #Predicate { $0.syncError != nil }))) ?? []).count
        let workouts = ((try? env.context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.syncError != nil }))) ?? []).count
        return meals + workouts
    }

    // MARK: HealthKit
    private var healthKitSection: some View {
        section("Apple Salud") {
            HStack {
                Text("Permisos de escritura").font(CBFont.body).foregroundStyle(CB.textPrimary)
                Spacer()
                Text(healthGranted ? "concedidos" : "sin conceder")
                    .font(CBFont.caption).foregroundStyle(healthGranted ? CB.success : CB.estimated)
            }
            HStack(spacing: CBSpace.s3) {
                CBButton(title: "Solicitar permisos", style: .secondary, size: .sm, fullWidth: false) {
                    Task { _ = await env.health.requestAuthorization(); healthGranted = env.health.writeAuthorized() }
                }
                CBButton(title: "Importar de Salud", style: .secondary, size: .sm, fullWidth: false) {
                    env.importFromHealthKit()
                }
            }
            Text("Lee peso, pasos, sueño y kcal activas; escribe comidas y entrenos.")
                .font(CBFont.caption).foregroundStyle(CB.textTertiary)
        }
    }

    // MARK: Data
    private var dataSection: some View {
        section("Datos") {
            row("Exportar todo (JSON)") { Task { await export() } }
            Text("Recordatorio: las fotos de comida viven en el chat de Claude, no en la app.")
                .font(CBFont.caption).foregroundStyle(CB.textTertiary)
        }
    }

    // MARK: Programa
    private var programSection: some View {
        section("Programa") {
            row("Ver programa activo") { showProgram = true }
            Text("Se edita con el coach.").font(CBFont.caption).foregroundStyle(CB.textTertiary)
        }
    }

    private var aboutSection: some View {
        section("Acerca de") {
            HStack {
                Text("Versión").font(CBFont.body).foregroundStyle(CB.textPrimary)
                Spacer()
                Text("1.0 (1)").font(CBFont.mono(12)).foregroundStyle(CB.textTertiary)
            }
            row("Design System (galería)") { showGallery = true }
        }
    }

    // MARK: helpers
    private func testConnection() async {
        testResult = "Probando…"
        do { let h = try await env.api.health(); testResult = "OK · versión \(h.version)" }
        catch { testResult = (error as? APIError)?.errorDescription ?? "Falló" }
    }
    private func export() async {
        do {
            let data = try await env.api.exportAll()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cbum-export.json")
            try data.write(to: url)
            exportFile = ExportFile(url: url)
        } catch { testResult = "Export falló" }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CBSpace.s3) {
            Text(title).cbLabel(color: CB.textAccent)
            VStack(alignment: .leading, spacing: CBSpace.s3) { content() }.cbCard()
        }
    }
    private func row(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(CBFont.body).foregroundStyle(CB.textPrimary)
                Spacer()
                CBIcon(name: .chevronR, size: 16, color: CB.textTertiary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).cbLabel()
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(CBFont.mono(13)).foregroundStyle(CB.textPrimary)
                .padding(CBSpace.s3).background(CB.surfaceInput, in: RoundedRectangle(cornerRadius: CBRadius.sm))
        }
    }
    private func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).cbLabel()
            SecureField("••••••", text: text)
                .font(CBFont.mono(13)).foregroundStyle(CB.textPrimary)
                .padding(CBSpace.s3).background(CB.surfaceInput, in: RoundedRectangle(cornerRadius: CBRadius.sm))
        }
    }
}

// Wrapper para compartir el export.
#if canImport(UIKit)
struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct ActivityView: View { let url: URL; var body: some View { Text(url.absoluteString) } }
#endif

// Wrapper Identifiable para presentar el export en .sheet(item:).
struct ExportFile: Identifiable { let id = UUID(); let url: URL }
