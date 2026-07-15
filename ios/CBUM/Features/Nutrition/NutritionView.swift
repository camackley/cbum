import SwiftUI
import SwiftData

// Pantalla NUTRICIÓN (spec I4). Selector de día, mini anillos, meals agrupados por
// meal_group_id, editar/borrar item, vista semanal. La app NO captura fotos:
// el flujo de comida vive en el chat de Claude (estado vacío lo indica).
struct NutritionView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var dayOffset = 0          // 0 = hoy
    @State private var editingMeal: Meal?
    @State private var showWeekly = false

    private var day: String {
        let d = Calendar.bogota.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return CBDate.day(d)
    }

    var body: some View {
        VStack(spacing: 0) {
            CBHeader(title: "Nutrición", eyebrow: dayLabel,
                     actionIcon: .progress, action: { showWeekly = true })
            daySwitcher
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CB.bgApp)
        .sheet(item: $editingMeal) { meal in MealEditSheet(meal: meal) }
        .sheet(isPresented: $showWeekly) { WeeklyNutritionSheet() }
    }

    private var dayLabel: String {
        switch dayOffset {
        case 0: return "Hoy"
        case -1: return "Ayer"
        default:
            let d = Calendar.bogota.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            return CBDate.shortLabel(d)
        }
    }

    private var daySwitcher: some View {
        HStack {
            Button { withAnimation(CBMotion.tap) { dayOffset -= 1 } } label: {
                CBIcon(name: .chevronL, size: 22, color: CB.textSecondary)
            }.buttonStyle(.plain)
            Spacer()
            Text(day).font(CBFont.mono(13)).foregroundStyle(CB.textSecondary)
            Spacer()
            Button { if dayOffset < 0 { withAnimation(CBMotion.tap) { dayOffset += 1 } } } label: {
                CBIcon(name: .chevronR, size: 22, color: dayOffset < 0 ? CB.textSecondary : CB.surfacePressed)
            }.buttonStyle(.plain).disabled(dayOffset >= 0)
        }
        .padding(.horizontal, CBSpace.gutterScreen).padding(.bottom, CBSpace.s2)
    }

    @ViewBuilder
    private var content: some View {
        let meals = fetchMeals()
        if meals.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: CBSpace.s4) {
                    miniRings(meals)
                    ForEach(groupedMeals(meals), id: \.0) { group in
                        mealGroup(group.0, items: group.1)
                    }
                }
                .padding(.horizontal, CBSpace.gutterScreen)
                .padding(.bottom, CBSpace.s10)
            }
        }
    }

    private func miniRings(_ meals: [Meal]) -> some View {
        let intake = meals.reduce(Macros.zero) { $0 + $1.macros }
        let g = goals()
        return HStack(spacing: CBSpace.s5) {
            MacroRings(kcal: .init(consumed: intake.kcal, target: dbl(g, "target_kcal")),
                       protein: .init(consumed: intake.protein_g, target: dbl(g, "target_protein_g")),
                       carbs: .init(consumed: intake.carbs_g, target: dbl(g, "target_carbs_g")),
                       fat: .init(consumed: intake.fat_g, target: dbl(g, "target_fat_g")),
                       showLegend: true, diameter: 150)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CBSpace.s2)
    }

    private func mealGroup(_ groupId: String, items: [Meal]) -> some View {
        VStack(alignment: .leading, spacing: CBSpace.s2) {
            if let first = items.first {
                Text(CBDate.hour(fromTs: first.ts)).cbLabel()
            }
            ForEach(items, id: \.id) { meal in
                MealRow(name: meal.name, time: CBDate.hour(fromTs: meal.ts),
                        kcal: meal.kcal, protein: meal.proteinG, carbs: meal.carbsG, fat: meal.fatG,
                        badge: SourceBadge(source: meal.sourceRaw, portionBasis: meal.portionBasisRaw, confidence: meal.confidence),
                        onEdit: { editingMeal = meal })
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: CBSpace.s4) {
            Spacer()
            CBIcon(name: .camera, size: 48, color: CB.textTertiary)
            Text("Loguea con el coach 📷").cbDisplay(CBFont.Size.displaySM)
            Text("Mándale fotos de tu comida a Claude. La app las muestra y sincroniza — la captura vive en el chat.")
                .font(CBFont.bodySM).foregroundStyle(CB.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, CBSpace.s6)
            CBButton(title: "Abrir Claude", style: .secondary, size: .md, icon: .zap, fullWidth: false) { openCoach() }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: data
    private func fetchMeals() -> [Meal] {
        let d = day
        let meals = ((try? env.context.fetch(FetchDescriptor<Meal>(
            predicate: #Predicate { $0.date == d && $0.deleted == false }))) ?? [])
        return meals.sorted { $0.ts < $1.ts }
    }
    private func groupedMeals(_ meals: [Meal]) -> [(String, [Meal])] {
        var order: [String] = []
        var map: [String: [Meal]] = [:]
        for m in meals {
            if map[m.mealGroupId] == nil { order.append(m.mealGroupId) }
            map[m.mealGroupId, default: []].append(m)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
    private func goals() -> [String: String] {
        Dictionary(uniqueKeysWithValues: ((try? env.context.fetch(FetchDescriptor<Goal>())) ?? []).map { ($0.key, $0.value) })
    }
    private func dbl(_ d: [String: String], _ k: String) -> Double { Double(d[k] ?? "") ?? 0 }

    private func openCoach() {
        #if canImport(UIKit)
        if let url = URL(string: "claude://"), UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
        else if let web = URL(string: "https://claude.ai") { UIApplication.shared.open(web) }
        #endif
    }
}

// Sheet de edición de item (spec I4).
struct MealEditSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let meal: Meal

    @State private var quantity: Double = 0
    @State private var kcal: Double = 0
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fat: Double = 0

    private var hasPer100g: Bool { meal.per100g != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CBSpace.s5) {
                    Text(meal.name).cbDisplay(CBFont.Size.displaySM)
                    SourceBadge(source: meal.sourceRaw, portionBasis: meal.portionBasisRaw, confidence: meal.confidence)

                    if hasPer100g {
                        VStack(alignment: .leading, spacing: CBSpace.s2) {
                            Text("Cantidad (g)").cbLabel()
                            Stepper(value: $quantity, in: 0...2000, step: 5) {
                                Text("\(CBNumber.format(quantity, decimals: 0)) g").cbNumber(28)
                            }.tint(CB.bone)
                        }
                        livePreview
                    } else {
                        Text("Entrada manual — se marca estimada")
                            .font(CBFont.caption).foregroundStyle(CB.estimated)
                        macroField("Kcal", $kcal)
                        macroField("Proteína (g)", $protein)
                        macroField("Carbos (g)", $carbs)
                        macroField("Grasa (g)", $fat)
                    }

                    CBButton(title: "Guardar", style: .primary, size: .lg) { save() }
                    CBButton(title: "Borrar item", style: .destructive, size: .sm, fullWidth: false) {
                        env.deleteMeal(meal); dismiss()
                    }
                }
                .padding(CBSpace.gutterScreen)
            }
            .background(CB.bgApp)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            quantity = meal.quantityG ?? 100
            kcal = meal.kcal; protein = meal.proteinG; carbs = meal.carbsG; fat = meal.fatG
        }
    }

    // Recalculo en vivo (misma regla que el server: per_100g × g/100).
    private var livePreview: some View {
        let m = meal.per100g?.scaled(toGrams: quantity) ?? Macros.zero
        return HStack(spacing: CBSpace.s5) {
            previewMetric(CBNumber.format(m.kcal, decimals: 0), "kcal")
            previewMetric(CBNumber.format(m.protein_g, decimals: 0), "P")
            previewMetric(CBNumber.format(m.carbs_g, decimals: 0), "C")
            previewMetric(CBNumber.format(m.fat_g, decimals: 0), "G")
        }
        .cbCard()
    }
    private func previewMetric(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) { Text(v).cbNumber(22, color: CB.bone); Text(l).font(CBFont.caption).foregroundStyle(CB.textSecondary) }
            .frame(maxWidth: .infinity)
    }
    private func macroField(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label).font(CBFont.body).foregroundStyle(CB.textPrimary)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .font(CBFont.number(20)).foregroundStyle(CB.textPrimary).frame(width: 90)
        }
        .cbCard(padding: CBSpace.s3)
    }

    private func save() {
        if hasPer100g { env.updateMealQuantity(meal, quantityG: quantity) }
        else { env.updateMealMacros(meal, macros: Macros(kcal: kcal, protein_g: protein, carbs_g: carbs, fat_g: fat, fiber_g: meal.fiberG)) }
        dismiss()
    }
}
