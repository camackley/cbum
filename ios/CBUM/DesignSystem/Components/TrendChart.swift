import SwiftUI
import Charts

struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    var isPR: Bool = false
}

// Componente 11 — Gráfico de línea (Swift Charts).
// Línea bone sobre negro, puntos de PR marcados (verde + anillo), eje mínimo.
// Opcional: lecturas crudas como puntos tenues detrás (peso). yUnit etiqueta
// el último valor. Regla de honestidad: solo se pasan puntos VÁLIDOS
// (e1RM fuera de rango se omite aguas arriba; nunca se interpola).
struct TrendChart: View {
    let data: [TrendPoint]
    var rawReadings: [TrendPoint] = []      // puntos tenues detrás (peso crudo)
    var yUnit: String = ""
    var fill: Bool = false
    var height: CGFloat = 200

    private var latest: TrendPoint? { data.last }
    private var yDomain: ClosedRange<Double> {
        let vals = (data + rawReadings).map(\.value)
        guard let lo = vals.min(), let hi = vals.max(), hi > lo else {
            let base = vals.first ?? 0
            return (base - 1)...(base + 1)
        }
        let pad = (hi - lo) * 0.15
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CBSpace.s2) {
            if let latest {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(fmt(latest.value)).cbNumber(28, color: CB.bone)
                    Text(yUnit).font(CBFont.bodySM).foregroundStyle(CB.textSecondary)
                }
            }
            chart
                .frame(height: height)
        }
    }

    @ViewBuilder private var chart: some View {
        if data.isEmpty {
            emptyState
        } else {
            Chart {
                ForEach(rawReadings) { p in
                    PointMark(x: .value("Fecha", p.date), y: .value(yUnit, p.value))
                        .foregroundStyle(CB.textTertiary.opacity(0.35))
                        .symbolSize(18)
                }
                if fill {
                    ForEach(data) { p in
                        AreaMark(x: .value("Fecha", p.date), y: .value(yUnit, p.value))
                            .foregroundStyle(.linearGradient(colors: [CB.bone.opacity(0.18), .clear],
                                                             startPoint: .top, endPoint: .bottom))
                    }
                }
                ForEach(data) { p in
                    LineMark(x: .value("Fecha", p.date), y: .value(yUnit, p.value))
                        .foregroundStyle(CB.bone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                ForEach(data.filter(\.isPR)) { p in
                    PointMark(x: .value("Fecha", p.date), y: .value(yUnit, p.value))
                        .foregroundStyle(CB.success)
                        .symbolSize(90)
                        .annotation(position: .top, spacing: 2) {
                            Text("PR").font(CBFont.labelSmall).foregroundStyle(CB.success)
                        }
                }
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(CB.borderSubtle)
                    AxisValueLabel().font(CBFont.caption).foregroundStyle(CB.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .font(CBFont.caption).foregroundStyle(CB.textTertiary)
                }
            }
        }
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: CBRadius.md)
            .fill(CB.surfaceCard)
            .overlay(Text("Sin datos suficientes").font(CBFont.bodySM).foregroundStyle(CB.textTertiary))
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

#Preview {
    let start = Date(timeIntervalSince1970: 1_717_200_000)
    let pts = (0..<10).map { i -> TrendPoint in
        let day: TimeInterval = Double(i) * 345_600            // 4 días
        let value: Double = 92.0 + Double(i) * 0.9
        return TrendPoint(date: start.addingTimeInterval(day), value: value, isPR: i == 4 || i == 9)
    }
    return VStack(spacing: 24) {
        TrendChart(data: pts, yUnit: "kg", fill: true)
        TrendChart(data: [], yUnit: "kg")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CB.bgApp)
    .preferredColorScheme(.dark)
}
