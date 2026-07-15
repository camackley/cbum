import SwiftUI

struct StatDelta {
    enum Dir { case up, down, flat }
    var value: String       // "0.3"
    var dir: Dir
    var period: String      // "/sem"
    var good: Bool?         // true=success, false=alert, nil=neutral

    var color: Color {
        switch good {
        case .some(true): return CB.success
        case .some(false): return CB.alert
        case .none: return CB.textSecondary
        }
    }
    var icon: CBIconName? {
        switch dir {
        case .up: return .arrowUp
        case .down: return .arrowDown
        case .flat: return nil
        }
    }
}

// Componente 4 — Stat card: valor grande condensado + label uppercase +
// delta direccional opcional + estado "CALIBRANDO" (amber) para datos
// con muestra insuficiente. `accent` pinta el valor en bone.
struct StatCard: View {
    let label: String
    let value: String
    var unit: String? = nil
    var delta: StatDelta? = nil
    var calibrating: Bool = false
    var footnote: String? = nil
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: CBSpace.s2) {
            HStack {
                Text(label).cbLabel()
                Spacer(minLength: 0)
                if calibrating {
                    Text("CALIBRANDO")
                        .font(CBFont.labelSmall)
                        .tracking(CBFont.Size.labelSM * CBFont.labelTrackFactor)
                        .foregroundStyle(CB.estimated)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: CBRadius.sm)
                            .strokeBorder(CB.estimated, lineWidth: CBRadius.borderHair))
                }
            }

            // Bug 2 (I6): el valor grande no debe partirse en dos líneas ("+0.0"/"7").
            // lineLimit(1) + minimumScaleFactor lo mantienen en una línea; el sufijo
            // (unit) reserva su ancho como hermano fijo. Dígitos monoespaciados vía cbNumber.
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .cbNumber(CBFont.Size.dataMD,
                              color: calibrating ? CB.textTertiary : (accent ? CB.bone : CB.textPrimary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit).font(CBFont.bodySM).foregroundStyle(CB.textSecondary)
                        .lineLimit(1).layoutPriority(1)
                }
                Spacer(minLength: 0)
            }

            if let delta {
                HStack(spacing: 4) {
                    if let icon = delta.icon { CBIcon(name: icon, size: 14, color: delta.color) }
                    Text("\(delta.value)\(delta.period)")
                        .font(CBFont.bodySM).foregroundStyle(delta.color)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            if let footnote {
                Text(footnote).font(CBFont.caption).foregroundStyle(CB.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cbCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit ?? "")")
    }
}

#Preview {
    HStack(spacing: CBSpace.s3) {
        StatCard(label: "Peso-tendencia", value: "82.4", unit: "kg",
                 delta: .init(value: "0.3", dir: .down, period: "/sem", good: true))
        StatCard(label: "TDEE", value: "2 780", unit: "kcal",
                 calibrating: true, footnote: "14 días de datos")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CB.bgApp)
    .preferredColorScheme(.dark)
}
