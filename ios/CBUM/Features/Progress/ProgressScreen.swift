import SwiftUI

// Pantalla PROGRESO (spec I4 + I5). Tabs Fuerza / Volumen / Cuerpo / Recuperación.
struct ProgressScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @State private var vm: ProgressViewModel?
    @State private var tab: Tab = .fuerza
    @State private var selectedWeek: String?
    @State private var showPicker = false

    enum Tab: String, CaseIterable, Identifiable {
        case fuerza, volumen, cuerpo, recuperacion
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fuerza: return "Fuerza"
            case .volumen: return "Volumen"
            case .cuerpo: return "Cuerpo"
            case .recuperacion: return "Recup."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            CBHeader(title: "Progreso")
            segmented
            if let vm {
                ScrollView {
                    VStack(alignment: .leading, spacing: CBSpace.s5) {
                        switch tab {
                        case .fuerza: fuerza(vm)
                        case .volumen: volumen(vm)
                        case .cuerpo: cuerpo(vm)
                        case .recuperacion: recuperacion(vm)
                        }
                    }
                    .padding(CBSpace.gutterScreen)
                }
            } else { Spacer() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CB.bgApp)
        .task {
            if vm == nil { vm = ProgressViewModel(env: env) }
            applyRouterTab()
            await vm?.loadOverview()
        }
        // HOY›DORMIR pide RECUPERACIÓN aunque la pantalla ya esté montada.
        .onChange(of: router.progressTab) { _, _ in applyRouterTab() }
    }

    private func applyRouterTab() {
        guard let sub = router.progressTab else { return }
        switch sub {
        case "fuerza": tab = .fuerza
        case "volumen": tab = .volumen
        case "cuerpo": tab = .cuerpo
        case "recuperacion": tab = .recuperacion
        default: break
        }
        router.progressTab = nil
    }

    private var segmented: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { t in
                Button { withAnimation(CBMotion.tap) { tab = t } } label: {
                    Text(t.title.uppercased())
                        .font(CBFont.labelSmall).tracking(CBFont.Size.labelSM * CBFont.labelTrackFactor)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(tab == t ? CB.textOnAccent : CB.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(tab == t ? CB.bone : CB.surfaceInput, in: RoundedRectangle(cornerRadius: CBRadius.sm))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, CBSpace.gutterScreen).padding(.bottom, CBSpace.s3)
    }

    // MARK: Fuerza
    @ViewBuilder
    private func fuerza(_ vm: ProgressViewModel) -> some View {
        let exName = env.allExercises().first { $0.id == vm.selectedExerciseId }?.name ?? "Elige ejercicio"
        Button { showPicker = true } label: {
            HStack {
                Text(exName).cbDisplay(CBFont.Size.displaySM)
                Spacer()
                CBIcon(name: .chevronD, size: 20, color: CB.textSecondary)
            }.cbCard()
        }.buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            SubstituteSheet(options: vm.exercisesWithHistory, title: "Ejercicio") { ex in
                vm.selectedExerciseId = ex.id
                showPicker = false
                Task { await vm.loadExercise() }
            }
        }

        let points = vm.e1rmPoints()
        if points.isEmpty {
            emptyNote("Sin sets válidos para graficar (e1RM solo dentro del rango de validez).")
        } else {
            chartCard("e1RM en el tiempo") {
                TrendChart(data: points, yUnit: "kg", fill: true,
                           chartId: "strength.e1rm.\(vm.selectedExerciseId ?? "")", decimals: 1,
                           emptyMessage: "Sin sets en este rango", emptyActionHint: "cambia a TODO")
            }
        }

        if let best = vm.exerciseProgress?.best_sets, !best.isEmpty {
            VStack(alignment: .leading, spacing: CBSpace.s2) {
                Text("Mejores sets").cbLabel()
                ForEach(Array(best.prefix(8).enumerated()), id: \.offset) { _, s in
                    HStack {
                        Text("\(CBNumber.smart(s.weight_kg)) kg × \(s.reps) @ RIR \(s.rir)")
                            .font(CBFont.bodySemibold).foregroundStyle(CB.textPrimary)
                        Spacer()
                        Text(s.date).font(CBFont.mono(11)).foregroundStyle(CB.textTertiary)
                    }
                }
            }.cbCard()
        }
    }

    // MARK: Volumen
    @ViewBuilder
    private func volumen(_ vm: ProgressViewModel) -> some View {
        let weeks = vm.availableWeeks()
        if weeks.count > 1 {
            HStack {
                Text("Semana").cbLabel()
                Spacer()
                Picker("Semana", selection: Binding(get: { selectedWeek ?? weeks.last ?? "" }, set: { selectedWeek = $0 })) {
                    ForEach(weeks, id: \.self) { Text($0).tag($0) }
                }.tint(CB.bone)
            }
        }
        let data = vm.volumeData(week: selectedWeek)
        if data.isEmpty { emptyNote("Aún no hay volumen registrado esta semana.") }
        else {
            VStack(alignment: .leading, spacing: CBSpace.s3) {
                Text("Sets efectivos · objetivo 10–20").cbLabel()
                VolumeBars(data: data)
            }.cbCard()
        }
    }

    // MARK: Cuerpo
    @ViewBuilder
    private func cuerpo(_ vm: ProgressViewModel) -> some View {
        if let e = vm.energy {
            chartCard("Peso-tendencia") {
                TrendChart(data: vm.weightTrendPoints(), rawReadings: vm.rawWeightPoints(),
                           yUnit: "kg", fill: false, chartId: "body.weight", decimals: 1,
                           emptyMessage: "Sin pesajes en este rango",
                           emptyActionHint: "cambia a TODO o revisa el puente de la báscula")
            }

            HStack(spacing: CBSpace.s3) {
                StatCard(label: "TDEE", value: e.tdee.kcal > 0 ? CBNumber.format(e.tdee.kcal, decimals: 0) : "—", unit: "kcal",
                         calibrating: e.tdee.status == "calibrating", accent: e.tdee.status == "adaptive")
                rateCard(e.goal)
            }

            // Composición (I5 §4): recomposición grasa%↓ + masa magra↑.
            let fat = vm.bodyFatPoints(), lean = vm.leanMassPoints()
            if !fat.isEmpty || !lean.isEmpty {
                chartCard("Composición · recomposición") {
                    CompositionChart(bodyFat: fat, leanMass: lean)
                }
            }
        } else { emptyNote("Sin datos de energía todavía.") }
    }

    // MARK: Recuperación (I5 §3)
    @ViewBuilder
    private func recuperacion(_ vm: ProgressViewModel) -> some View {
        if let rec = vm.recovery {
            if !rec.data_gaps.isEmpty { gapsBanner(rec.data_gaps) }

            chartCard("Sueño · fases por noche") {
                SleepStackedBars(nights: vm.sleepNights(), needHours: vm.sleepNeedHours,
                                 avg7d: rec.sleep.avg_7d_hours, midpointDrift: rec.sleep.midpoint_drift_hours)
            }
            chartCard("Frecuencia cardíaca en reposo") {
                BaselineBandChart(points: vm.rhrPoints(), baseline: rec.rhr.baseline_28d,
                                  bandLow: rec.rhr.baseline_28d.map { $0 * 0.97 },
                                  bandHigh: rec.rhr.baseline_28d.map { $0 * 1.03 },
                                  yUnit: "bpm", chartId: "recovery.rhr", decimals: 0)
            }
            chartCard("Variabilidad · HRV") {
                BaselineBandChart(points: vm.hrvPoints(), baseline: rec.hrv.baseline_28d_ms,
                                  bandLow: rec.hrv.baseline_28d_ms.map { $0 * 0.85 }, bandHigh: nil,
                                  yUnit: "ms", chartId: "recovery.hrv", decimals: 0)
            }
        } else {
            emptyNote("Sin datos de recuperación todavía. Importa de Salud en Ajustes.")
        }
    }

    private func gapsBanner(_ gaps: [String]) -> some View {
        HStack(alignment: .top, spacing: CBSpace.s2) {
            CBIcon(name: .clock, size: 16, color: CB.estimated)
            VStack(alignment: .leading, spacing: 2) {
                Text("Huecos de datos — revisa SyncFit / el puente").cbLabel(color: CB.estimated)
                ForEach(gaps, id: \.self) { g in
                    Text(g).font(CBFont.caption).foregroundStyle(CB.textTertiary)
                }
            }
            Spacer()
        }
        .cbCard(stroke: CB.estimated)
    }

    private func rateCard(_ g: EnergyStatus.Goal) -> some View {
        let actual = g.rate_actual_kg_per_week
        let onTrack = g.on_track
        return StatCard(
            label: "Ritmo",
            value: actual.map { CBNumber.signed($0, decimals: 2) } ?? "—",
            unit: "kg/sem",
            delta: g.rate_target_kg_per_week.map { StatDelta(value: "obj \(CBNumber.signed($0, decimals: 2))", dir: .flat, period: "", good: onTrack) },
            footnote: onTrack == true ? "en objetivo" : (onTrack == false ? "fuera de objetivo" : nil))
    }

    @ViewBuilder
    private func chartCard(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CBSpace.s2) {
            Text(title).cbLabel()
            content()
        }.cbCard()
    }

    private func emptyNote(_ t: String) -> some View {
        Text(t).font(CBFont.bodySM).foregroundStyle(CB.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading).cbCard()
    }
}
