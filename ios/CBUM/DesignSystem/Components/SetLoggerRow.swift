import SwiftUI

// Stepper grande reutilizable, usable con pulgar y manos sudadas (≥48pt).
private struct BigStepper: View {
    let label: String
    let valueText: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(label).cbLabel()
            HStack(spacing: 0) {
                stepButton(.minus, action: onMinus)
                Text(valueText)
                    .cbNumber(28)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(CB.surfaceInput)
                stepButton(.plus, action: onPlus)
            }
            .clipShape(RoundedRectangle(cornerRadius: CBRadius.md))
            .overlay(RoundedRectangle(cornerRadius: CBRadius.md).strokeBorder(CB.borderDefault, lineWidth: CBRadius.borderHair))
        }
    }

    private func stepButton(_ icon: CBIconName, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CBIcon(name: icon, size: 24, color: CB.textPrimary)
                .frame(width: 56, height: 60)
                .background(CB.surfacePressed)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == .minus ? "Restar \(label)" : "Sumar \(label)")
    }
}

// Componente 6 — SetLoggerRow (el estrella).
// Estados: pendiente (tenue), activo (steppers + RIR + guardar),
// guardado (colapsado + check), PR (borde success + trofeo + flash).
struct SetLoggerRow: View {
    enum State { case pending, active, saved, pr }

    let setNumber: Int
    var isWarmup: Bool = false
    @Binding var weight: Double
    @Binding var reps: Int
    @Binding var rir: Int?
    var incrementKg: Double = 2.5
    var state: State = .active
    var e1rm: Double? = nil
    var onSave: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onToggleWarmup: (() -> Void)? = nil

    @SwiftUI.State private var flash = false

    var body: some View {
        switch state {
        case .active: activeView
        default: collapsedView
        }
    }

    // MARK: Active
    private var activeView: some View {
        VStack(spacing: CBSpace.s3) {
            HStack {
                Text(isWarmup ? "CALENT." : "SET \(setNumber)").cbLabel(color: CB.textPrimary)
                Spacer()
                Button { onToggleWarmup?() } label: {
                    Text(isWarmup ? "· calentamiento" : "marcar calent.")
                        .font(CBFont.caption).foregroundStyle(CB.textTertiary)
                }.buttonStyle(.plain)
            }

            HStack(spacing: CBSpace.s3) {
                BigStepper(label: "Peso (kg)", valueText: fmt(weight),
                           onMinus: { weight = max(0, weight - incrementKg) },
                           onPlus: { weight += incrementKg })
                BigStepper(label: "Reps", valueText: "\(reps)",
                           onMinus: { reps = max(1, reps - 1) },
                           onPlus: { reps += 1 })
            }

            RIRSelector(value: $rir, size: .lg, showCaption: true)

            CBButton(title: "Guardar set", style: .primary, size: .lg, icon: .check,
                     isEnabled: rir != nil) {
                onSave?()
            }
        }
        .cbCard(fill: CB.surfaceCard, stroke: CB.borderAccent)
    }

    // MARK: Collapsed (pending / saved / pr)
    private var collapsedView: some View {
        let isPR = state == .pr
        let isPending = state == .pending
        return Button {
            if !isPending { onEdit?() }
        } label: {
            HStack(spacing: CBSpace.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: CBRadius.sm)
                        .fill(isPR ? CB.success : CB.surfacePressed)
                        .frame(width: 40, height: 40)
                    if isPR {
                        CBIcon(name: .trophy, size: 20, color: CB.textOnAccent)
                    } else if state == .saved {
                        CBIcon(name: .check, size: 18, color: CB.success)
                    } else {
                        Text("\(setNumber)").cbNumber(18, color: CB.textTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isWarmup ? "Calentamiento" : "Set \(setNumber)")
                        .font(CBFont.bodySemibold).foregroundStyle(CB.textPrimary)
                    if let rir {
                        Text("\(fmt(weight)) kg × \(reps) @ RIR \(rir)")
                            .font(CBFont.bodySM).foregroundStyle(CB.textSecondary)
                    } else {
                        Text("Pendiente").font(CBFont.bodySM).foregroundStyle(CB.textTertiary)
                    }
                }
                Spacer()
                if let e1rm, state != .pending {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(fmt(e1rm)).cbNumber(20, color: isPR ? CB.success : CB.textPrimary)
                        Text("e1RM").font(CBFont.caption).foregroundStyle(CB.textTertiary)
                    }
                }
                if isPR {
                    Text("PR").font(CBFont.display(16)).foregroundStyle(CB.success)
                }
            }
            .cbCard(fill: isPR ? CB.success.opacity(0.08) : CB.surfaceCard,
                    stroke: isPR ? CB.success : CB.borderDefault)
            .opacity(isPending ? 0.5 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: CBRadius.md)
                    .fill(CB.success.opacity(flash ? 0.25 : 0))
            )
        }
        .buttonStyle(.plain)
        .disabled(isPending)
        .onAppear {
            if isPR {
                withAnimation(CBMotion.pr) { flash = true }
                withAnimation(CBMotion.easeOut.delay(0.4)) { flash = false }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

#Preview {
    struct Demo: View {
        @State var w1 = 80.0; @State var r1 = 8; @State var rir1: Int? = 2
        @State var w2 = 82.5; @State var r2 = 8; @State var rir2: Int? = 2
        @State var w3 = 85.0; @State var r3 = 8; @State var rir3: Int? = 1
        @State var w4 = 82.5; @State var r4 = 8; @State var rir4: Int? = nil
        var body: some View {
            ScrollView {
                VStack(spacing: CBSpace.s3) {
                    SetLoggerRow(setNumber: 1, weight: $w1, reps: $r1, rir: $rir1, state: .saved, e1rm: 106.7)
                    SetLoggerRow(setNumber: 2, weight: $w2, reps: $r2, rir: $rir2, state: .active, e1rm: nil)
                    SetLoggerRow(setNumber: 3, weight: $w3, reps: $r3, rir: $rir3, state: .pr, e1rm: 113.3)
                    SetLoggerRow(setNumber: 4, weight: $w4, reps: $r4, rir: $rir4, state: .pending)
                }.padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CB.bgApp)
        }
    }
    return Demo().preferredColorScheme(.dark)
}
