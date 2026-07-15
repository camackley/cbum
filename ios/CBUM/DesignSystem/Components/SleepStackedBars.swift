import SwiftUI
import Charts

// Una noche de sueño con fases (delta §R1). Horas por fase; días sin dato = ausentes
// (hueco real, jamás interpolado).
struct SleepNight: Identifiable {
    let id = UUID()
    let date: Date
    let deep: Double
    let rem: Double
    let core: Double
    let awake: Double
}

// PROGRESO›RECUPERACIÓN — barras apiladas por noche (I5 §3): deep/rem/core en tonos
// bone→gray, awake en alert 30%; línea de necesidad (sleep_need_hours); rango global.
// Subtítulo: promedio 7d + drift de midpoint. Gaps = huecos reales.
struct SleepStackedBars: View {
    let nights: [SleepNight]
    var needHours: Double = 7.0
    var avg7d: Double? = nil
    var midpointDrift: Double? = nil
    var chartId: String = "recovery.sleep"
    var height: CGFloat = 220

    @State private var range: ChartRange = .m3

    private struct Seg: Identifiable { let id = UUID(); let date: Date; let phase: String; let hours: Double }

    // Orden de apilado bottom→top y escala de color (bone→gray, awake alert 30%).
    private static let order = ["Profundo", "Core", "REM", "Despierto"]
    private static let scale: KeyValuePairs<String, Color> = [
        "Profundo": CB.bone, "Core": CB.gray300, "REM": CB.gray500, "Despierto": CB.alert.opacity(0.3),
    ]

    private var visible: [SleepNight] { nights.filter { range.contains($0.date) } }

    private var segments: [Seg] {
        visible.flatMap { n in
            [Seg(date: n.date, phase: "Profundo", hours: n.deep),
             Seg(date: n.date, phase: "Core", hours: n.core),
             Seg(date: n.date, phase: "REM", hours: n.rem),
             Seg(date: n.date, phase: "Despierto", hours: n.awake)].filter { $0.hours > 0 }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CBSpace.s2) {
            CBRangePicker(selection: $range)
                .onChange(of: range) { _, r in ChartRangeStore.save(chartId, r) }
            subtitle
            if visible.isEmpty {
                emptyState
            } else {
                chart.frame(height: height)
            }
        }
        .onAppear { range = ChartRangeStore.load(chartId) }
    }

    private var subtitle: some View {
        HStack(spacing: CBSpace.s3) {
            if let avg7d {
                Text("prom 7d \(CBNumber.format(avg7d, decimals: 1)) h").font(CBFont.caption).foregroundStyle(CB.textSecondary)
            }
            if let midpointDrift {
                Text("drift \(CBNumber.format(midpointDrift, decimals: 1)) h").font(CBFont.caption).foregroundStyle(CB.textTertiary)
            }
            Spacer()
        }
    }

    private var chart: some View {
        Chart {
            ForEach(segments) { s in
                BarMark(x: .value("Noche", s.date, unit: .day),
                        y: .value("Horas", s.hours))
                    .foregroundStyle(by: .value("Fase", s.phase))
            }
            RuleMark(y: .value("Necesidad", needHours))
                .foregroundStyle(CB.textSecondary.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("necesidad \(CBNumber.format(needHours, decimals: 1))h")
                        .font(CBFont.caption).foregroundStyle(CB.textTertiary)
                }
        }
        .chartForegroundStyleScale(Self.scale)
        .chartLegend(position: .bottom, spacing: CBSpace.s2)
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

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: CBRadius.md).fill(CB.surfaceRaised)
            .frame(height: height)
            .overlay(Text("Sin noches de sueño en este rango")
                .font(CBFont.bodySM).foregroundStyle(CB.textSecondary))
    }
}

#Preview {
    let start = Calendar.bogota.date(byAdding: .day, value: -20, to: Date())!
    let nights = (0..<20).compactMap { i -> SleepNight? in
        if i == 8 || i == 9 { return nil }   // gap real
        let d = Calendar.bogota.date(byAdding: .day, value: i, to: start)!
        return SleepNight(date: d, deep: 1.1, rem: 1.5, core: 4.2, awake: 0.6)
    }
    return SleepStackedBars(nights: nights, needHours: 7.0, avg7d: 7.1, midpointDrift: 0.6)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CB.bgApp)
        .preferredColorScheme(.dark)
}
