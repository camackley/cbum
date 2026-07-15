import SwiftUI

// Componente 10 — Meal row. Nombre, hora, kcal + P/C/G, SourceBadge; tap → editar.
struct MealRow: View {
    let name: String
    let time: String            // "13:20"
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let badge: SourceBadge
    var onEdit: (() -> Void)? = nil

    var body: some View {
        Button {
            onEdit?()
        } label: {
            HStack(spacing: CBSpace.s3) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: CBSpace.s2) {
                        Text(name).font(CBFont.bodySemibold).foregroundStyle(CB.textPrimary)
                            .lineLimit(1)
                        badge
                    }
                    HStack(spacing: CBSpace.s2) {
                        Text(time).font(CBFont.mono(11)).foregroundStyle(CB.textTertiary)
                        macro("P", protein)
                        macro("C", carbs)
                        macro("G", fat)
                    }
                }
                Spacer(minLength: CBSpace.s2)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(kcal))").cbNumber(22)
                    Text("kcal").font(CBFont.caption).foregroundStyle(CB.textTertiary)
                }
                if onEdit != nil {
                    CBIcon(name: .chevronR, size: 18, color: CB.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, CBSpace.s3)
            .padding(.horizontal, CBSpace.s4)
            .background(CB.surfaceCard, in: RoundedRectangle(cornerRadius: CBRadius.md))
            .overlay(RoundedRectangle(cornerRadius: CBRadius.md).strokeBorder(CB.borderDefault, lineWidth: CBRadius.borderHair))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onEdit == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(Int(kcal)) kilocalorías, \(time)")
        .accessibilityHint(onEdit != nil ? "Toca para editar" : "")
    }

    private func macro(_ label: String, _ v: Double) -> some View {
        Text("\(label) \(Int(v))g").font(CBFont.caption).foregroundStyle(CB.textSecondary)
    }
}

#Preview {
    VStack(spacing: CBSpace.s2) {
        MealRow(name: "Pollo + arroz + aguacate", time: "13:20", kcal: 642,
                protein: 48, carbs: 71, fat: 18,
                badge: SourceBadge(kind: .weighed), onEdit: {})
        MealRow(name: "Batido post-entreno", time: "18:05", kcal: 310,
                protein: 40, carbs: 32, fat: 4,
                badge: SourceBadge(kind: .label), onEdit: {})
        MealRow(name: "Almuerzo restaurante (estimado)", time: "13:40", kcal: 780,
                protein: 35, carbs: 90, fat: 28,
                badge: SourceBadge(kind: .estimated, lowConfidence: true), onEdit: {})
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CB.bgApp)
    .preferredColorScheme(.dark)
}
