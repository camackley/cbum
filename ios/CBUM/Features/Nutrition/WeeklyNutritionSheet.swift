import SwiftUI
import SwiftData

// Vista semanal de nutrición (spec I4): adherencia (días dentro de ±5% de kcal
// target), % weighed promedio, días sin marcar completos.
struct WeeklyNutritionSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CBSpace.s4) {
                    let stats = compute()
                    HStack(spacing: CBSpace.s3) {
                        StatCard(label: "Adherencia", value: "\(Int(stats.adherence * 100))", unit: "%",
                                 footnote: "días ±5% de kcal target")
                        StatCard(label: "% Pesado", value: "\(Int(stats.weighedPct * 100))", unit: "%",
                                 footnote: "promedio 7 días")
                    }
                    ForEach(stats.days, id: \.date) { d in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.date).font(CBFont.mono(12)).foregroundStyle(CB.textSecondary)
                                Text(d.complete ? "logueado completo" : "sin marcar")
                                    .font(CBFont.caption)
                                    .foregroundStyle(d.complete ? CB.success : CB.estimated)
                            }
                            Spacer()
                            Text("\(Int(d.kcal))").cbNumber(20, color: d.withinTarget ? CB.success : CB.textPrimary)
                            Text("kcal").font(CBFont.caption).foregroundStyle(CB.textTertiary)
                        }
                        .cbCard(padding: CBSpace.s3)
                    }
                }
                .padding(CBSpace.gutterScreen)
            }
            .background(CB.bgApp)
            .navigationTitle("Semana")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    struct DayStat { let date: String; let kcal: Double; let complete: Bool; let withinTarget: Bool; let weighedPct: Double }
    struct WeekStats { let adherence: Double; let weighedPct: Double; let days: [DayStat] }

    private func compute() -> WeekStats {
        let target = Double(env.fetchGoal(key: "target_kcal")?.value ?? "") ?? 0
        var days: [DayStat] = []
        for i in 0..<7 {
            let d = Calendar.bogota.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            let ds = CBDate.day(d)
            let meals = ((try? env.context.fetch(FetchDescriptor<Meal>(
                predicate: #Predicate { $0.date == ds && $0.deleted == false }))) ?? [])
            let kcal = meals.reduce(0.0) { $0 + $1.kcal }
            let weighed = meals.isEmpty ? 0 : Double(meals.filter { $0.portionBasisRaw == "weighed" }.count) / Double(meals.count)
            let complete = env.fetchDayFlag(date: ds)?.loggingComplete ?? false
            let within = target > 0 && abs(kcal - target) / target <= 0.05
            days.append(DayStat(date: ds, kcal: kcal, complete: complete, withinTarget: within, weighedPct: weighed))
        }
        let completeDays = days.filter { $0.complete }
        let adherence = completeDays.isEmpty ? 0 : Double(completeDays.filter { $0.withinTarget }.count) / Double(completeDays.count)
        let withMeals = days.filter { $0.kcal > 0 }
        let weighedAvg = withMeals.isEmpty ? 0 : withMeals.reduce(0.0) { $0 + $1.weighedPct } / Double(withMeals.count)
        return WeekStats(adherence: adherence, weighedPct: weighedAvg, days: days)
    }
}
