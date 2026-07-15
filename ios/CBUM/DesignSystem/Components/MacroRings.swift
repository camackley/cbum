import SwiftUI

struct MacroValue {
    var consumed: Double
    var target: Double
    var fraction: Double { target > 0 ? consumed / target : 0 }
    var over: Bool { consumed > target && target > 0 }
    var remaining: Double { max(0, target - consumed) }
}

// Componente 3 — Anillo de macros.
// Anillos concéntricos: kcal (exterior) + proteína (bone) + carbos + grasa.
// Números de kcal al centro; excedido → color alert. Leyenda P/C/G debajo.
struct MacroRings: View {
    let kcal: MacroValue
    let protein: MacroValue
    let carbs: MacroValue
    let fat: MacroValue
    var showLegend: Bool = true
    var diameter: CGFloat = 200

    private var ringWidth: CGFloat { diameter * 0.075 }
    private var gap: CGFloat { ringWidth * 0.55 }

    var body: some View {
        VStack(spacing: CBSpace.s4) {
            ZStack {
                ring(kcal, color: CB.bone, inset: 0)
                ring(protein, color: CB.bone, inset: (ringWidth + gap) * 1)
                ring(carbs, color: CB.gray300, inset: (ringWidth + gap) * 2)
                ring(fat, color: CB.gray400, inset: (ringWidth + gap) * 3)

                VStack(spacing: 0) {
                    Text("\(Int(kcal.consumed))")
                        .cbNumber(diameter * 0.24, color: kcal.over ? CB.alert : CB.textPrimary)
                    Text("/ \(Int(kcal.target)) KCAL")
                        .font(CBFont.mono(11))
                        .foregroundStyle(CB.textSecondary)
                    Text(kcal.over ? "+\(Int(kcal.consumed - kcal.target))" : "\(Int(kcal.remaining)) restan")
                        .font(CBFont.caption)
                        .foregroundStyle(kcal.over ? CB.alert : CB.textTertiary)
                        .padding(.top, 2)
                }
            }
            .frame(width: diameter, height: diameter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Macros del día")
            .accessibilityValue("\(Int(kcal.consumed)) de \(Int(kcal.target)) kilocalorías. Proteína \(Int(protein.consumed)) de \(Int(protein.target)) gramos.")

            if showLegend {
                HStack(spacing: CBSpace.s5) {
                    legend("P", protein, CB.bone)
                    legend("C", carbs, CB.gray300)
                    legend("G", fat, CB.gray400)
                }
            }
        }
    }

    private func ring(_ v: MacroValue, color: Color, inset: CGFloat) -> some View {
        let d = diameter - inset * 2
        return ZStack {
            Circle()
                .stroke(CB.surfaceInput, lineWidth: ringWidth)
            Circle()
                .trim(from: 0, to: min(1, v.fraction))
                .stroke(v.over ? CB.alert : color,
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: d, height: d)
    }

    private func legend(_ label: String, _ v: MacroValue, _ color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(v.over ? CB.alert : color).frame(width: 7, height: 7)
                Text(label).font(CBFont.label).foregroundStyle(CB.textSecondary)
            }
            Text("\(Int(v.consumed))")
                .cbNumber(20, color: v.over ? CB.alert : CB.textPrimary)
            Text("/ \(Int(v.target))g").font(CBFont.caption).foregroundStyle(CB.textTertiary)
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        MacroRings(kcal: .init(consumed: 1840, target: 2650),
                   protein: .init(consumed: 142, target: 190),
                   carbs: .init(consumed: 168, target: 260),
                   fat: .init(consumed: 61, target: 78))
        MacroRings(kcal: .init(consumed: 2720, target: 2650),
                   protein: .init(consumed: 205, target: 190),
                   carbs: .init(consumed: 240, target: 260),
                   fat: .init(consumed: 70, target: 78),
                   showLegend: false, diameter: 120)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CB.bgApp)
    .preferredColorScheme(.dark)
}
