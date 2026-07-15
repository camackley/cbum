import SwiftUI

// Catálogo interactivo de los 12 componentes del design system CBUM,
// renderizados con datos realistas de gym. Accesible desde Ajustes (debug)
// y como Preview. Cumple la Aceptación de I1.
struct ComponentGallery: View {
    // Estado para componentes interactivos
    @State private var tab: CBTab = .hoy
    @State private var rir: Int? = 2
    @State private var slWeight = 82.5
    @State private var slReps = 8
    @State private var slRir: Int? = nil
    @State private var rest = 92
    @State private var range: ChartRange = .m3

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CBSpace.s8) {
                section("01 · Tab bar + Header") {
                    CBHeader(title: "Hoy", eyebrow: "Lun · 14 Jul", actionIcon: .settings, action: {})
                    CBTabBar(active: $tab)
                }
                section("02 · Botones") {
                    CBButton(title: "Empezar entreno", style: .primary, icon: .dumbbell) {}
                    CBButton(title: "Sustituir", style: .secondary, size: .md, iconRight: .swap) {}
                    CBButton(title: "Descartar sesión", style: .destructive, size: .sm, fullWidth: false) {}
                }
                section("03 · Anillo de macros") {
                    MacroRings(kcal: .init(consumed: 1840, target: 2650),
                               protein: .init(consumed: 142, target: 190),
                               carbs: .init(consumed: 168, target: 260),
                               fat: .init(consumed: 61, target: 78))
                    .frame(maxWidth: .infinity)
                }
                section("04 · Stat card") {
                    HStack(spacing: CBSpace.s3) {
                        StatCard(label: "Peso-tendencia", value: "82.4", unit: "kg",
                                 delta: .init(value: "0.3", dir: .down, period: "/sem", good: true))
                        StatCard(label: "TDEE", value: "2 780", unit: "kcal",
                                 calibrating: true, footnote: "14 días de datos")
                    }
                }
                section("05 · Exercise card") {
                    ExerciseCard(name: "Press banca", sets: 4, repRange: 6...8, targetRIR: 2,
                                 suggestedKg: 82.5, suggestionReason: "subiste: 4×8@2 la vez pasada",
                                 lastSession: "10 Jul · 80kg×8@2", setsCompleted: 1, status: .active,
                                 onStart: {}, onSubstitute: {})
                }
                section("06 · Set logger row (estrella)") {
                    SetLoggerRow(setNumber: 2, weight: $slWeight, reps: $slReps, rir: $slRir,
                                 state: .active, onSave: { slRir = slRir ?? 2 })
                    SetLoggerRow(setNumber: 1, weight: .constant(80), reps: .constant(8),
                                 rir: .constant(2), state: .saved, e1rm: 106.7)
                    SetLoggerRow(setNumber: 3, weight: .constant(85), reps: .constant(8),
                                 rir: .constant(1), state: .pr, e1rm: 113.3)
                }
                section("07 · Selector RIR") {
                    RIRSelector(value: $rir)
                }
                section("08 · Rest timer") {
                    RestTimer(duration: 150, remaining: $rest, onAddThirty: { rest += 30 }, onSkip: { rest = 0 })
                        .frame(maxWidth: .infinity)
                }
                section("09 · Badge de fuente") {
                    HStack(spacing: CBSpace.s3) {
                        SourceBadge(kind: .weighed)
                        SourceBadge(kind: .label)
                        SourceBadge(kind: .estimated, lowConfidence: true)
                    }
                }
                section("10 · Meal row") {
                    MealRow(name: "Pollo + arroz + aguacate", time: "13:20", kcal: 642,
                            protein: 48, carbs: 71, fat: 18, badge: SourceBadge(kind: .weighed), onEdit: {})
                    MealRow(name: "Batido post-entreno", time: "18:05", kcal: 310,
                            protein: 40, carbs: 32, fat: 4, badge: SourceBadge(kind: .label), onEdit: {})
                }
                section("11 · Gráfico de línea") {
                    TrendChart(data: sampleE1RM, yUnit: "kg", fill: true)
                }
                section("12 · Barras de volumen") {
                    VolumeBars(data: [
                        .init(muscle: "Pecho", sets: 14, min: 12, max: 20),
                        .init(muscle: "Espalda", sets: 22, min: 14, max: 22),
                        .init(muscle: "Cuádriceps", sets: 8, min: 12, max: 18),
                    ])
                }
                section("Extra · PR toast") {
                    PRToast(exercise: "Press banca", detail: "e1RM 113.3 kg · +2.5 vs anterior", onDismiss: {})
                }

                // ── V2 (I5/I6) ──────────────────────────────────────────────
                section("V2 · Selector de rango (charts)") {
                    CBRangePicker(selection: $range)
                }
                section("V2 · Tríada de HOY + chip de recuperación") {
                    TodayTriad(
                        eat: .init(kcalConsumed: 1830, kcalTarget: 2650),
                        train: .init(name: "Upper A", isRest: false, completed: false, exerciseCount: 6),
                        sleep: .init(hours: 6.95, deep: 1.2, rem: 1.55, core: 4.2),
                        recoveryState: "caution")
                }
                section("V2 · Chips de recuperación (todos los estados)") {
                    RecoveryChip(state: "good")
                    RecoveryChip(state: "caution")
                    RecoveryChip(state: "low")
                    RecoveryChip(state: "no_data")
                }
                section("V2 · Sueño apilado por fases + necesidad") {
                    SleepStackedBars(nights: sampleNights, needHours: 7.0, avg7d: 7.1, midpointDrift: 0.6)
                }
                section("V2 · Banda de baseline (RHR con punto fuera)") {
                    BaselineBandChart(points: sampleRHR, baseline: 58, bandLow: 58 * 0.97, bandHigh: 58 * 1.03,
                                      yUnit: "bpm", chartId: "gallery.rhr", decimals: 0)
                }
                section("V2 · Composición (recomposición)") {
                    CompositionChart(bodyFat: sampleFat, leanMass: sampleLean, chartId: "gallery.comp")
                }
                section("V2 · TrendChart con rango + scrubbing") {
                    TrendChart(data: sampleWeight, rawReadings: sampleWeightRaw, yUnit: "kg",
                               chartId: "gallery.weight", decimals: 1)
                }
            }
            .padding(CBSpace.gutterScreen)
        }
        .background(CB.bgApp)
        .preferredColorScheme(.dark)
    }

    private var sampleE1RM: [TrendPoint] {
        let start = Date(timeIntervalSince1970: 1_717_200_000)
        return (0..<10).map { i in
            let day: TimeInterval = Double(i) * 345_600            // 4 días
            let value: Double = 100.0 + Double(i) * 1.3
            return TrendPoint(date: start.addingTimeInterval(day), value: value, isPR: i == 4 || i == 9)
        }
    }

    // Datos de ejemplo V2
    private var sampleNights: [SleepNight] {
        let start = Calendar.bogota.date(byAdding: .day, value: -18, to: Date()) ?? Date()
        return (0..<18).compactMap { i in
            if i == 7 || i == 8 { return nil }   // hueco real
            let d = Calendar.bogota.date(byAdding: .day, value: i, to: start) ?? Date()
            let w = Double((i * 13) % 7 - 3) / 20.0
            return SleepNight(date: d, deep: 1.05 + w * 0.5, rem: 1.45 + w, core: 4.35 - w * 0.5, awake: 0.55)
        }
    }
    private var sampleRHR: [TrendPoint] {
        let start = Calendar.bogota.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        return (0..<28).compactMap { i in
            if (20...23).contains(i) { return nil }
            let d = Calendar.bogota.date(byAdding: .day, value: i, to: start) ?? Date()
            return TrendPoint(date: d, value: i == 27 ? 61 : 58)
        }
    }
    private var sampleFat: [TrendPoint] {
        let start = Calendar.bogota.date(byAdding: .day, value: -84, to: Date()) ?? Date()
        return (0..<12).map { i in
            let d = Calendar.bogota.date(byAdding: .day, value: i * 7, to: start) ?? Date()
            return TrendPoint(date: d, value: 16.8 - Double(i) * 0.12)
        }
    }
    private var sampleLean: [TrendPoint] {
        let start = Calendar.bogota.date(byAdding: .day, value: -84, to: Date()) ?? Date()
        return (0..<12).map { i in
            let d = Calendar.bogota.date(byAdding: .day, value: i * 7, to: start) ?? Date()
            return TrendPoint(date: d, value: 68.5 + Double(i) * 0.18)
        }
    }
    private var sampleWeight: [TrendPoint] {
        let start = Calendar.bogota.date(byAdding: .day, value: -120, to: Date()) ?? Date()
        return (0..<120).map { i in
            let d = Calendar.bogota.date(byAdding: .day, value: i, to: start) ?? Date()
            return TrendPoint(date: d, value: 84.0 - Double(i) * 0.03)
        }
    }
    private var sampleWeightRaw: [TrendPoint] {
        sampleWeight.enumerated().filter { $0.offset % 3 == 0 }.map {
            TrendPoint(date: $0.element.date, value: $0.element.value + Double(($0.offset % 5) - 2) * 0.2)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CBSpace.s3) {
            Text(title).cbLabel(color: CB.textAccent)
            content()
        }
    }
}

#Preview {
    ComponentGallery()
}
