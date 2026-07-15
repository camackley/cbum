import SwiftUI

// Componente 7 — Selector RIR (Reps In Reserve) segmentado 0–5.
// Un tap; segmento seleccionado se llena de bone (texto negro).
// RIR 0 = "al fallo" (rojo). SIN preselección → obliga registro consciente.
struct RIRSelector: View {
    @Binding var value: Int?     // nil = sin registrar (precisión: no preseleccionar)
    var size: Size = .lg
    var showCaption: Bool = true

    enum Size { case lg, sm }

    private var height: CGFloat { size == .lg ? CBSpace.touch : 34 }
    private var fontSize: CGFloat { size == .lg ? 18 : 15 }

    private static let captions: [Int: String] = [
        0: "al fallo", 1: "muy duro", 2: "duro", 3: "moderado", 4: "cómodo", 5: "fácil"
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0...5, id: \.self) { rir in
                    let selected = value == rir
                    Button {
                        withAnimation(CBMotion.tap) { value = rir }
                    } label: {
                        Text("\(rir)")
                            .font(CBFont.number(fontSize))
                            .foregroundStyle(segmentText(rir, selected: selected))
                            .frame(maxWidth: .infinity)
                            .frame(height: height)
                            .background(selected ? (rir == 0 ? CB.alert : CB.bone) : CB.surfaceInput,
                                        in: RoundedRectangle(cornerRadius: CBRadius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: CBRadius.sm)
                                    .strokeBorder(rir == 0 && !selected ? CB.alert.opacity(0.5) : .clear,
                                                  lineWidth: CBRadius.borderHair)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("RIR \(rir)")
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
            if showCaption {
                Text(value.flatMap { Self.captions[$0] }.map { "RIR \(value!) · \($0)" } ?? "Elige RIR")
                    .font(CBFont.caption)
                    .foregroundStyle(value == 0 ? CB.alert : CB.textSecondary)
            }
        }
    }

    private func segmentText(_ rir: Int, selected: Bool) -> Color {
        if selected { return rir == 0 ? CB.white : CB.textOnAccent }
        return CB.textPrimary
    }
}

#Preview {
    struct Demo: View {
        @State var a: Int? = 2
        @State var b: Int? = nil
        @State var c: Int? = 0
        var body: some View {
            VStack(spacing: 24) {
                RIRSelector(value: $a)
                RIRSelector(value: $b)
                RIRSelector(value: $c, size: .sm, showCaption: false)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CB.bgApp)
        }
    }
    return Demo().preferredColorScheme(.dark)
}
