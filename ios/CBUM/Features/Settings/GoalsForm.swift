import SwiftUI
import SwiftData

// Form de objetivos (spec I4 · keys de contracts §1 goals). Guardar → PUT (outbox).
struct GoalsForm: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]

    private struct Field { let key: String; let label: String; let unit: String; let numeric: Bool }
    private let fields: [Field] = [
        .init(key: "target_kcal", label: "Kcal objetivo", unit: "kcal", numeric: true),
        .init(key: "target_protein_g", label: "Proteína objetivo", unit: "g", numeric: true),
        .init(key: "target_carbs_g", label: "Carbos objetivo", unit: "g", numeric: true),
        .init(key: "target_fat_g", label: "Grasa objetivo", unit: "g", numeric: true),
        .init(key: "goal_weight_kg", label: "Peso meta", unit: "kg", numeric: true),
        .init(key: "goal_rate_kg_per_week", label: "Ritmo (− pierde)", unit: "kg/sem", numeric: true),
        .init(key: "sex", label: "Sexo (m/f)", unit: "", numeric: false),
        .init(key: "age", label: "Edad", unit: "años", numeric: true),
        .init(key: "height_cm", label: "Altura", unit: "cm", numeric: true),
        .init(key: "activity_factor", label: "Factor actividad", unit: "1.2–1.9", numeric: true),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CBSpace.s3) {
                    Text("El coach puede cambiar esto por ti.").font(CBFont.caption).foregroundStyle(CB.textTertiary)
                    ForEach(fields, id: \.key) { f in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.label).font(CBFont.body).foregroundStyle(CB.textPrimary)
                                if !f.unit.isEmpty { Text(f.unit).font(CBFont.caption).foregroundStyle(CB.textTertiary) }
                            }
                            Spacer()
                            TextField("—", text: binding(f.key))
                                .keyboardType(f.numeric ? .numbersAndPunctuation : .default)
                                .multilineTextAlignment(.trailing)
                                .font(CBFont.number(18)).foregroundStyle(CB.textPrimary).frame(width: 100)
                        }
                        .cbCard(padding: CBSpace.s3)
                    }
                    CBButton(title: "Guardar objetivos", style: .primary, size: .lg) {
                        env.saveGoals(values); dismiss()
                    }
                }
                .padding(CBSpace.gutterScreen)
            }
            .background(CB.bgApp)
            .navigationTitle("Objetivos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .onAppear { load() }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }
    private func load() {
        let goals = (try? env.context.fetch(FetchDescriptor<Goal>())) ?? []
        values = Dictionary(uniqueKeysWithValues: goals.map { ($0.key, $0.value) })
    }
}
