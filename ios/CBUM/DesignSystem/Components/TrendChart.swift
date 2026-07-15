import SwiftUI
import Charts
#if canImport(UIKit)
import UIKit
#endif

struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    var isPR: Bool = false
}

// Componente 11 — Gráfico de tendencia V2 (Swift Charts) — delta §R6 / I6.
// · Línea EMA/tendencia bone 2pt protagonista; lecturas crudas gray400 al 30%.
// · Selector de rango (1M/3M/6M/1A/TODO, default 3M) persistido por chart cuando
//   se pasa `chartId`; la serie se filtra por rango ANTES de graficar (el EMA ya
//   viene calculado sobre la serie completa aguas arriba → carry-forward intacto).
// · Scrubbing: drag → línea vertical + lollipop (valor + fecha "14 jul"), haptic
//   .selection al cambiar de punto; al soltar persiste 2s y se desvanece.
// · Dominio Y: min/max de la serie VISIBLE ±5% (nunca el de la serie completa).
// · Ejes: 4–5 ticks; "d MMM" (≤6M) o "MMM yy" (mayores).
// · Estado vacío con acción (nunca un área en blanco).
struct TrendChart: View {
    let data: [TrendPoint]
    var rawReadings: [TrendPoint] = []
    var yUnit: String = ""
    var fill: Bool = false
    var height: CGFloat = 200
    var chartId: String? = nil
    var decimals: Int = 1
    var emptyMessage: String = "Sin datos en este rango"
    var emptyActionHint: String? = nil

    @State private var range: ChartRange = .m3
    @State private var scrub: TrendPoint? = nil
    @State private var scrubClearTask: Task<Void, Never>? = nil

    private var hasPicker: Bool { chartId != nil }

    private var visibleData: [TrendPoint] {
        guard hasPicker else { return data }
        return data.filter { range.contains($0.date) }
    }
    private var visibleRaw: [TrendPoint] {
        guard hasPicker else { return rawReadings }
        return rawReadings.filter { range.contains($0.date) }
    }

    private var latest: TrendPoint? { visibleData.last }

    // Dominio Y de la serie VISIBLE ±5% (causa secundaria del Bug 1: usar el dominio
    // completo aplasta la tendencia reciente).
    private var yDomain: ClosedRange<Double> {
        let vals = (visibleData + visibleRaw).map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        guard hi > lo else { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.05
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CBSpace.s2) {
            if hasPicker {
                CBRangePicker(selection: $range)
                    .onChange(of: range) { _, r in
                        if let id = chartId { ChartRangeStore.save(id, r) }
                        scrub = nil
                    }
            }
            header
            chart.frame(height: height)
        }
        .onAppear { if let id = chartId { range = ChartRangeStore.load(id) } }
    }

    @ViewBuilder private var header: some View {
        if let scrub {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(CBNumber.smart(scrub.value, decimals: decimals)).cbNumber(28, color: CB.bone)
                Text(yUnit).font(CBFont.bodySM).foregroundStyle(CB.textSecondary)
                Spacer()
                Text(CBDate.dayMonth(scrub.date)).font(CBFont.mono(13)).foregroundStyle(CB.textTertiary)
            }
        } else if let latest {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(CBNumber.smart(latest.value, decimals: decimals)).cbNumber(28, color: CB.bone)
                Text(yUnit).font(CBFont.bodySM).foregroundStyle(CB.textSecondary)
            }
        }
    }

    @ViewBuilder private var chart: some View {
        if visibleData.isEmpty {
            emptyState
        } else {
            Chart {
                ForEach(visibleRaw) { p in
                    PointMark(x: .value("Fecha", p.date), y: .value(yUnit, p.value))
                        .foregroundStyle(CB.gray400.opacity(0.30))
                        .symbolSize(18)
                }
                if fill {
                    ForEach(visibleData) { p in
                        AreaMark(x: .value("Fecha", p.date), y: .value(yUnit, p.value))
                            .foregroundStyle(.linearGradient(colors: [CB.bone.opacity(0.18), .clear],
                                                             startPoint: .top, endPoint: .bottom))
                    }
                }
                ForEach(visibleData) { p in
                    LineMark(x: .value("Fecha", p.date), y: .value(yUnit, p.value))
                        .foregroundStyle(CB.bone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                ForEach(visibleData.filter(\.isPR)) { p in
                    PointMark(x: .value("Fecha", p.date), y: .value(yUnit, p.value))
                        .foregroundStyle(CB.success)
                        .symbolSize(90)
                        .annotation(position: .top, spacing: 2) {
                            Text("PR").font(CBFont.labelSmall).foregroundStyle(CB.success)
                        }
                }
                if let scrub {
                    RuleMark(x: .value("Fecha", scrub.date))
                        .foregroundStyle(CB.gray500.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Fecha", scrub.date), y: .value(yUnit, scrub.value))
                        .foregroundStyle(CB.bone)
                        .symbolSize(70)
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
                    AxisGridLine().foregroundStyle(CB.borderSubtle.opacity(0.5))
                    AxisValueLabel(format: range.usesYearAxis && hasPicker
                                   ? Date.FormatStyle().month(.abbreviated).year(.twoDigits)
                                   : Date.FormatStyle().day().month(.abbreviated))
                        .font(CBFont.caption).foregroundStyle(CB.textTertiary)
                }
            }
            .environment(\.locale, CBNumber.locale)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in updateScrub(at: v.location, proxy: proxy, geo: geo) }
                            .onEnded { _ in scheduleScrubClear() })
                }
            }
        }
    }

    private func updateScrub(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        scrubClearTask?.cancel()
        guard let plotFrame = proxy.plotFrame else { return }
        let xInPlot = location.x - geo[plotFrame].origin.x
        guard let date: Date = proxy.value(atX: xInPlot, as: Date.self) else { return }
        guard let nearest = visibleData.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else { return }
        if scrub?.id != nearest.id {
            hapticSelection()
            scrub = nearest
        }
    }

    private func scheduleScrubClear() {
        scrubClearTask?.cancel()
        scrubClearTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { withAnimation(CBMotion.easeOut) { scrub = nil } }
        }
    }

    private func hapticSelection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: CBRadius.md)
            .fill(CB.surfaceRaised)
            .overlay(
                VStack(spacing: CBSpace.s2) {
                    Text(emptyMessage).font(CBFont.bodySM).foregroundStyle(CB.textSecondary)
                    if let emptyActionHint {
                        Text(emptyActionHint).font(CBFont.caption).foregroundStyle(CB.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(CBSpace.s4)
            )
    }
}

#Preview {
    let start = Date(timeIntervalSince1970: 1_717_200_000)
    let pts = (0..<40).map { i -> TrendPoint in
        let day: TimeInterval = Double(i) * 86_400
        let value: Double = 92.0 - Double(i) * 0.12
        return TrendPoint(date: start.addingTimeInterval(day), value: value, isPR: i == 20 || i == 39)
    }
    return VStack(spacing: 24) {
        TrendChart(data: pts, yUnit: "kg", fill: true, chartId: "preview.weight")
        TrendChart(data: [], yUnit: "kg", chartId: "preview.empty",
                   emptyMessage: "Sin pesajes en 3M", emptyActionHint: "cambia a TODO o revisa el puente de la báscula")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CB.bgApp)
    .preferredColorScheme(.dark)
}
