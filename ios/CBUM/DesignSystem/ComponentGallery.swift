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
