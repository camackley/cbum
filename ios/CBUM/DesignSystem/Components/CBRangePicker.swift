import SwiftUI

// Selector de rango global de charts (delta §R6 / I6 Bug 1): 1M · 3M · 6M · 1A · TODO,
// default 3M, persistido por chart en UserDefaults. La serie se filtra por rango
// ANTES de graficar; el EMA se calcula sobre la serie completa aguas arriba.
enum ChartRange: String, CaseIterable, Identifiable {
    case m1, m3, m6, y1, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .m1: return "1M"
        case .m3: return "3M"
        case .m6: return "6M"
        case .y1: return "1A"
        case .all: return "TODO"
        }
    }

    /// Días de la ventana; nil = todo el historial.
    var days: Int? {
        switch self {
        case .m1: return 30
        case .m3: return 90
        case .m6: return 180
        case .y1: return 365
        case .all: return nil
        }
    }

    /// Rangos ≤ 6M usan eje "d MMM"; mayores (1A/TODO) usan "MMM yy".
    var usesYearAxis: Bool { self == .y1 || self == .all }

    func startDate(now: Date = Date()) -> Date? {
        guard let days else { return nil }
        return Calendar.bogota.date(byAdding: .day, value: -days, to: now)
    }

    func contains(_ date: Date, now: Date = Date()) -> Bool {
        guard let start = startDate(now: now) else { return true }
        return date >= start
    }
}

// Persistencia por chart (UserDefaults). Default 3M.
enum ChartRangeStore {
    static func load(_ chartId: String) -> ChartRange {
        UserDefaults.standard.string(forKey: key(chartId)).flatMap(ChartRange.init(rawValue:)) ?? .m3
    }
    static func save(_ chartId: String, _ range: ChartRange) {
        UserDefaults.standard.set(range.rawValue, forKey: key(chartId))
    }
    private static func key(_ id: String) -> String { "cbum.chartRange.\(id)" }
}

struct CBRangePicker: View {
    @Binding var selection: ChartRange

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChartRange.allCases) { r in
                let active = r == selection
                Button {
                    withAnimation(CBMotion.tap) { selection = r }
                } label: {
                    Text(r.label)
                        .font(CBFont.labelSmall)
                        .tracking(CBFont.Size.labelSM * CBFont.labelTrackFactor)
                        .foregroundStyle(active ? CB.textOnAccent : CB.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(active ? CB.bone : CB.surfaceInput,
                                    in: RoundedRectangle(cornerRadius: CBRadius.sm))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Rango \(r.label)"))
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

#Preview {
    struct Demo: View {
        @State var r: ChartRange = .m3
        var body: some View {
            VStack(spacing: 20) {
                CBRangePicker(selection: $r)
                Text("Seleccionado: \(r.label)").font(CBFont.body).foregroundStyle(CB.textPrimary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CB.bgApp)
        }
    }
    return Demo().preferredColorScheme(.dark)
}
