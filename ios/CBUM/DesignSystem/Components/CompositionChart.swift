import SwiftUI
import Charts

// PROGRESO›CUERPO — composición (I5 §4). Doble chart grasa% (alert tenue) + masa
// magra (success tenue), un solo selector de rango. Es LA gráfica de recomposición:
// masa magra ↑ con grasa ↓. Escalas muy distintas → dos paneles con eje propio.
struct CompositionChart: View {
    let bodyFat: [TrendPoint]    // %
    let leanMass: [TrendPoint]   // kg
    var chartId: String = "body.composition"

    @State private var range: ChartRange = .m3

    var body: some View {
        VStack(alignment: .leading, spacing: CBSpace.s3) {
            CBRangePicker(selection: $range)
                .onChange(of: range) { _, r in ChartRangeStore.save(chartId, r) }
            panel("Grasa corporal", points: bodyFat.filter { range.contains($0.date) },
                  color: CB.alert.opacity(0.75), unit: "%", decimals: 1)
            panel("Masa magra", points: leanMass.filter { range.contains($0.date) },
                  color: CB.success.opacity(0.75), unit: "kg", decimals: 1)
        }
        .onAppear { range = ChartRangeStore.load(chartId) }
    }

    @ViewBuilder private func panel(_ label: String, points: [TrendPoint], color: Color, unit: String, decimals: Int) -> some View {
        VStack(alignment: .leading, spacing: CBSpace.s1) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(label).cbLabel()
                Spacer()
                if let last = points.last {
                    Text(CBNumber.format(last.value, decimals: decimals)).cbNumber(20, color: color).lineLimit(1)
                    Text(unit).font(CBFont.caption).foregroundStyle(CB.textSecondary)
                }
            }
            if points.isEmpty {
                RoundedRectangle(cornerRadius: CBRadius.md).fill(CB.surfaceRaised).frame(height: 120)
                    .overlay(Text("Sin datos en este rango").font(CBFont.bodySM).foregroundStyle(CB.textSecondary))
            } else {
                Chart {
                    ForEach(points) { p in
                        LineMark(x: .value("Fecha", p.date), y: .value(unit, p.value))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Fecha", p.date), y: .value(unit, p.value))
                            .foregroundStyle(color.opacity(0.4))
                            .symbolSize(16)
                    }
                }
                .chartYScale(domain: yDomain(points))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(CB.borderSubtle)
                        AxisValueLabel().font(CBFont.caption).foregroundStyle(CB.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: range.usesYearAxis
                                       ? Date.FormatStyle().month(.abbreviated).year(.twoDigits)
                                       : Date.FormatStyle().day().month(.abbreviated))
                            .font(CBFont.caption).foregroundStyle(CB.textTertiary)
                    }
                }
                .environment(\.locale, CBNumber.locale)
                .frame(height: 120)
            }
        }
    }

    private func yDomain(_ points: [TrendPoint]) -> ClosedRange<Double> {
        let vals = points.map(\.value)
        guard let lo = vals.min(), let hi = vals.max(), hi > lo else {
            let b = vals.first ?? 0; return (b - 1)...(b + 1)
        }
        let pad = (hi - lo) * 0.10
        return (lo - pad)...(hi + pad)
    }
}
