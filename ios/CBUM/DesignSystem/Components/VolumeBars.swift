import SwiftUI

struct VolumeDatum: Identifiable {
    let id = UUID()
    let muscle: String
    let sets: Int
    var min: Int = 10
    var max: Int = 20
}

// Componente 12 — Barras de volumen semanal (sets efectivos por músculo).
// Banda de rango objetivo (min–max) visible detrás; barra bone en zona,
// gris bajo objetivo, amber sobre objetivo.
struct VolumeBars: View {
    let data: [VolumeDatum]
    var maxScale: Int? = nil       // tope del eje; auto si nil

    private var scaleMax: Int {
        maxScale ?? Swift.max(data.map { Swift.max($0.sets, $0.max) }.max() ?? 20, 20)
    }

    var body: some View {
        VStack(spacing: CBSpace.s3) {
            ForEach(data) { d in
                row(d)
            }
        }
    }

    private func color(for d: VolumeDatum) -> Color {
        if d.sets < d.min { return CB.textSecondary }   // bajo objetivo → gris
        if d.sets > d.max { return CB.estimated }        // sobre objetivo → amber
        return CB.bone                                   // en zona → bone
    }

    private func row(_ d: VolumeDatum) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(d.muscle).cbLabel(color: CB.textPrimary)
                Spacer()
                Text("\(d.sets)").cbNumber(18, color: color(for: d))
                Text("sets").font(CBFont.caption).foregroundStyle(CB.textTertiary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                let unit = w / CGFloat(scaleMax)
                ZStack(alignment: .leading) {
                    // track
                    RoundedRectangle(cornerRadius: CBRadius.sm).fill(CB.surfaceInput)
                    // banda objetivo
                    RoundedRectangle(cornerRadius: CBRadius.sm)
                        .fill(CB.bone.opacity(0.14))
                        .frame(width: unit * CGFloat(d.max - d.min))
                        .offset(x: unit * CGFloat(d.min))
                    // barra
                    RoundedRectangle(cornerRadius: CBRadius.sm)
                        .fill(color(for: d))
                        .frame(width: Swift.min(w, unit * CGFloat(d.sets)))
                }
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(d.muscle): \(d.sets) sets efectivos, objetivo \(d.min) a \(d.max)")
    }
}

#Preview {
    VolumeBars(data: [
        .init(muscle: "Pecho", sets: 14, min: 12, max: 20),
        .init(muscle: "Espalda", sets: 22, min: 14, max: 22),
        .init(muscle: "Cuádriceps", sets: 8, min: 12, max: 18),
        .init(muscle: "Hombros", sets: 16, min: 10, max: 20),
    ])
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CB.bgApp)
    .preferredColorScheme(.dark)
}
