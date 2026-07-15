import SwiftUI

// Pantalla PROGRESO (spec I4). Tabs Fuerza / Volumen / Cuerpo.
struct ProgressScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm: ProgressViewModel?
    @State private var tab: Tab = .fuerza
    @State private var selectedWeek: String?
    @State private var showPicker = false

    enum Tab: String, CaseIterable { case fuerza = "Fuerza", volumen = "Volumen", cuerpo = "Cuerpo" }

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
            await vm?.loadOverview()
        }
    }

    private var segmented: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { withAnimation(CBMotion.tap) { tab = t } } label: {
                    Text(t.rawValue.uppercased())
                        .font(CBFont.label).tracking(CBFont.Size.label * CBFont.labelTrackFactor)
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
            VStack(alignment: .leading, spacing: CBSpace.s2) {
                Text("e1RM en el tiempo").cbLabel()
                TrendChart(data: points, yUnit: "kg", fill: true)
            }.cbCard()
        }

        if let best = vm.exerciseProgress?.best_sets, !best.isEmpty {
            VStack(alignment: .leading, spacing: CBSpace.s2) {
                Text("Mejores sets").cbLabel()
                ForEach(Array(best.prefix(8).enumerated()), id: \.offset) { _, s in
                    HStack {
                        Text("\(fmt(s.weight_kg)) kg × \(s.reps) @ RIR \(s.rir)")
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
            VStack(alignment: .leading, spacing: CBSpace.s2) {
                Text("Peso-tendencia").cbLabel()
                TrendChart(data: vm.weightTrendPoints(), rawReadings: vm.rawWeightPoints(), yUnit: "kg", fill: false)
            }.cbCard()

            HStack(spacing: CBSpace.s3) {
                StatCard(label: "TDEE", value: e.tdee.kcal > 0 ? String(Int(e.tdee.kcal)) : "—", unit: "kcal",
                         calibrating: e.tdee.status == "calibrating", accent: e.tdee.status == "adaptive")
                rateCard(e.goal)
            }
        } else { emptyNote("Sin datos de energía todavía.") }
    }

    private func rateCard(_ g: EnergyStatus.Goal) -> some View {
        let actual = g.rate_actual_kg_per_week
        let onTrack = g.on_track
        return StatCard(
            label: "Ritmo",
            value: actual.map { String(format: "%+.2f", $0) } ?? "—",
            unit: "kg/sem",
            delta: g.rate_target_kg_per_week.map { StatDelta(value: "obj \(String(format: "%+.2f", $0))", dir: .flat, period: "", good: onTrack) },
            footnote: onTrack == true ? "en objetivo" : (onTrack == false ? "fuera de objetivo" : nil))
    }

    private func emptyNote(_ t: String) -> some View {
        Text(t).font(CBFont.bodySM).foregroundStyle(CB.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading).cbCard()
    }
    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}
