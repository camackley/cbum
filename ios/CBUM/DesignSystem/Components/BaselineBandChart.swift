import SwiftUI
import Charts

// PROGRESO›RECUPERACIÓN — línea diaria vs banda del baseline 28d (I5 §3).
// RHR: banda baseline ±3%; HRV: umbral −15% (banda inferior). Puntos fuera de banda
// en alert. Días sin dato = huecos reales (puntos, sin línea interpolada).
struct BaselineBandChart: View {
    let points: [TrendPoint]
    let baseline: Double?
    let bandLow: Double?         // valor absoluto; alert si value < bandLow
    let bandHigh: Double?        // valor absoluto; alert si value > bandHigh
    var yUnit: String = ""
    var chartId: String
    var decimals: Int = 0
    var height: CGFloat = 180

    @State private var range: ChartRange = .m3

    private var visible: [TrendPoint] { points.filter { range.contains($0.date) } }

    private func outOfBand(_ v: Double) -> Bool {
        if let lo = bandLow, v < lo { return true }
        if let hi = bandHigh, v > hi { return true }
        return false
    }

    private var yDomain: ClosedRange<Double> {
        var vals = visible.map(\.value)
        if let baseline { vals.append(baseline) }
        if let bandLow { vals.append(bandLow) }
        if let bandHigh { vals.append(bandHigh) }
        guard let lo = vals.min(), let hi = vals.max(), hi > lo else {
            let b = vals.first ?? 0; return (b - 5)...(b + 5)
        }
        let pad = (hi - lo) * 0.08
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CBSpace.s2) {
            CBRangePicker(selection: $range)
                .onChange(of: range) { _, r in ChartRangeStore.save(chartId, r) }
            if visible.isEmpty {
                RoundedRectangle(cornerRadius: CBRadius.md).fill(CB.surfaceRaised).frame(height: height)
                    .overlay(Text("Sin lecturas en este rango").font(CBFont.bodySM).foregroundStyle(CB.textSecondary))
            } else {
                chart.frame(height: height)
            }
        }
        .onAppear { range = ChartRangeStore.load(chartId) }
    }

    private var chart: some View {
        Chart {
            // Banda del baseline (ambos límites → rectángulo; solo inferior → regla umbral).
            if let lo = bandLow, let hi = bandHigh {
                RectangleMark(yStart: .value("lo", lo), yEnd: .value("hi", hi))
                    .foregroundStyle(CB.bone.opacity(0.10))
            } else if let lo = bandLow {
                RuleMark(y: .value("umbral", lo))
                    .foregroundStyle(CB.alert.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let baseline {
                RuleMark(y: .value("baseline", baseline))
                    .foregroundStyle(CB.textSecondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("base \(CBNumber.format(baseline, decimals: decimals))")
                            .font(CBFont.caption).foregroundStyle(CB.textTertiary)
                    }
            }
            // Lecturas diarias (puntos; huecos reales donde no hay dato).
            ForEach(visible) { p in
                PointMark(x: .value("Fecha", p.date), y: .value(yUnit, p.value))
                    .foregroundStyle(outOfBand(p.value) ? CB.alert : CB.bone)
                    .symbolSize(outOfBand(p.value) ? 45 : 26)
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
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
    }
}

#Preview {
    let start = Calendar.bogota.date(byAdding: .day, value: -30, to: Date())!
    let pts = (0..<30).compactMap { i -> TrendPoint? in
        if (18...22).contains(i) { return nil }   // gap desde ~2 semanas
        let d = Calendar.bogota.date(byAdding: .day, value: i, to: start)!
        return TrendPoint(date: d, value: i == 29 ? 61 : 58)
    }
    return BaselineBandChart(points: pts, baseline: 58, bandLow: 58 * 0.97, bandHigh: 58 * 1.03,
                             yUnit: "bpm", chartId: "preview.rhr")
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CB.bgApp)
        .preferredColorScheme(.dark)
}
