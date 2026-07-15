import SwiftUI

// Componente 5 — Exercise card (objetivo del día).
// Nombre, prescripción "4×6–8 @ RIR 2", peso sugerido (bone destacado),
// dots de progreso de sets, y botón sustituir. status: upcoming/active/done.
struct ExerciseCard: View {
    enum Status { case upcoming, active, done }

    let name: String
    let sets: Int
    let repRange: ClosedRange<Int>
    let targetRIR: Int
    var suggestedKg: Double?
    var suggestionReason: String? = nil       // ej. "subiste: 4×8@2"
    var lastSession: String? = nil            // ej. "10 Jul · 80kg×8@2"
    var setsCompleted: Int = 0
    var status: Status = .upcoming
    var compact: Bool = false
    var onStart: (() -> Void)? = nil
    var onSubstitute: (() -> Void)? = nil

    private var scheme: String {
        let rr = repRange.lowerBound == repRange.upperBound
            ? "\(repRange.lowerBound)"
            : "\(repRange.lowerBound)–\(repRange.upperBound)"
        return "\(sets)×\(rr) @ RIR \(targetRIR)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CBSpace.s3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).cbDisplay(CBFont.Size.displaySM)
                    Text(scheme).font(CBFont.bodyMedium).foregroundStyle(CB.textSecondary)
                }
                Spacer()
                if status == .done {
                    CBIcon(name: .check, size: 24, color: CB.success)
                }
            }

            // Dots de progreso de sets
            if !compact {
                HStack(spacing: 6) {
                    ForEach(0..<sets, id: \.self) { i in
                        Circle()
                            .fill(i < setsCompleted ? CB.bone : CB.surfaceInput)
                            .frame(width: 8, height: 8)
                    }
                    if setsCompleted > 0 {
                        Text("\(setsCompleted)/\(sets)")
                            .font(CBFont.caption).foregroundStyle(CB.textTertiary)
                            .padding(.leading, 4)
                    }
                }
            }

            if let suggestedKg {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("Sugerido").cbLabel()
                    Text("\(fmt(suggestedKg)) kg").cbNumber(28, color: CB.bone)
                }
                if let suggestionReason {
                    Text(suggestionReason).font(CBFont.caption).foregroundStyle(CB.textTertiary)
                }
            } else {
                Text("Sin historial · elige peso")
                    .font(CBFont.bodySM).foregroundStyle(CB.estimated)
            }

            if let lastSession {
                Text("Última: \(lastSession)").font(CBFont.caption).foregroundStyle(CB.textTertiary)
            }

            if !compact {
                HStack(spacing: CBSpace.s3) {
                    CBButton(title: status == .active ? "Continuar" : "Empezar",
                             style: status == .active ? .primary : .secondary,
                             size: .md, fullWidth: true) { onStart?() }
                    if onSubstitute != nil {
                        CBButton(title: "Sustituir", style: .secondary, size: .md,
                                 iconRight: .swap, fullWidth: false) { onSubstitute?() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cbCard(stroke: status == .active ? CB.borderAccent : CB.borderDefault)
        .opacity(status == .done ? 0.6 : 1)
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

#Preview {
    VStack(spacing: CBSpace.s3) {
        ExerciseCard(name: "Press banca", sets: 4, repRange: 6...8, targetRIR: 2,
                     suggestedKg: 82.5, suggestionReason: "subiste: 4×8@2 la vez pasada",
                     lastSession: "10 Jul · 80kg×8@2", setsCompleted: 1, status: .active,
                     onStart: {}, onSubstitute: {})
        ExerciseCard(name: "Remo con barra", sets: 4, repRange: 8...10, targetRIR: 2,
                     suggestedKg: nil, status: .upcoming, onStart: {}, onSubstitute: {})
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CB.bgApp)
    .preferredColorScheme(.dark)
}
