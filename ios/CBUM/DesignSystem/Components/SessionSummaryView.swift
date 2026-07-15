import SwiftUI

// Extra (design feedback) — resumen de fin de sesión: duración, sets, tonelaje,
// PRs y desglose por ejercicio.
struct SessionSummaryView: View {
    let duration: String
    let totalSets: Int
    let volumeKg: Double
    let prCount: Int
    let byMuscle: [(String, Int)]
    let exercises: [(name: String, sets: Int, topSet: String, isPR: Bool)]

    var body: some View {
        VStack(alignment: .leading, spacing: CBSpace.s5) {
            HStack(spacing: CBSpace.s3) {
                metric(duration, "duración")
                metric("\(totalSets)", "sets")
                metric(fmtVol(volumeKg), "kg vol.")
                if prCount > 0 { metric("\(prCount)", "PRs", color: CB.success) }
            }

            if !byMuscle.isEmpty {
                VStack(alignment: .leading, spacing: CBSpace.s2) {
                    Text("Sets efectivos por músculo").cbLabel()
                    ForEach(byMuscle, id: \.0) { m in
                        HStack {
                            Text(m.0).font(CBFont.body).foregroundStyle(CB.textPrimary)
                            Spacer()
                            Text("\(m.1)").cbNumber(18, color: CB.bone)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: CBSpace.s2) {
                Text("Ejercicios").cbLabel()
                ForEach(exercises, id: \.name) { e in
                    HStack {
                        if e.isPR { CBIcon(name: .trophy, size: 16, color: CB.success) }
                        Text(e.name).font(CBFont.bodySemibold).foregroundStyle(e.isPR ? CB.success : CB.textPrimary)
                        Spacer()
                        Text("\(e.sets)× · \(e.topSet)").font(CBFont.bodySM).foregroundStyle(CB.textSecondary)
                    }
                }
            }
        }
    }

    private func metric(_ value: String, _ label: String, color: Color = CB.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).cbNumber(28, color: color)
            Text(label).font(CBFont.caption).foregroundStyle(CB.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func fmtVol(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v / 1000) : String(Int(v))
    }
}

#Preview {
    ScrollView {
        SessionSummaryView(duration: "58:12", totalSets: 18, volumeKg: 12480, prCount: 2,
                           byMuscle: [("Pecho", 8), ("Espalda", 7)],
                           exercises: [("Press banca", 4, "85kg×8", true), ("Remo con barra", 4, "90kg×10", false)])
        .padding()
    }
    .background(CB.bgApp).preferredColorScheme(.dark)
}
