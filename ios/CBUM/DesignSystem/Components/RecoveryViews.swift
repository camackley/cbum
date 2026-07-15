import SwiftUI

// Estilo del estado de recuperación (copy honesto de I5 §2). Ningún estado sin regla
// explícita del delta §R5 (los produce el backend/FormulasKit).
struct RecoveryStateStyle {
    let short: String
    let long: String
    let color: Color

    init(_ state: String) {
        switch state {
        case "good":
            short = "RECUPERADO"; long = "RECUPERADO"; color = CB.success
        case "caution":
            short = "A MEDIAS"; long = "RECUPERACIÓN A MEDIAS — considera bajar volumen hoy"; color = CB.estimated
        case "low":
            short = "MAL RECUPERADO"; long = "MAL RECUPERADO — el coach lo sabe"; color = CB.alert
        default: // no_data
            short = "SIN DATOS"; long = "SIN DATOS DE SUEÑO — revisa el puente"; color = CB.textTertiary
        }
    }
}

// Chip de recovery_state para HOY (I5 §2).
struct RecoveryChip: View {
    let state: String
    var body: some View {
        let s = RecoveryStateStyle(state)
        return HStack(spacing: CBSpace.s2) {
            Circle().fill(s.color).frame(width: 8, height: 8)
            Text(s.long)
                .font(CBFont.label)
                .tracking(CBFont.Size.label * CBFont.labelTrackFactor)
                .foregroundStyle(s.color)
                .lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CBSpace.s3).padding(.vertical, CBSpace.s2)
        .background(s.color.opacity(0.10), in: RoundedRectangle(cornerRadius: CBRadius.sm))
        .overlay(RoundedRectangle(cornerRadius: CBRadius.sm).strokeBorder(s.color.opacity(0.4), lineWidth: CBRadius.borderHair))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recuperación: \(s.long)")
    }
}

// Mini-barra apilada de fases de una noche (deep/rem/core; awake se omite aquí).
struct SleepMiniBar: View {
    let deep: Double
    let rem: Double
    let core: Double
    var height: CGFloat = 8

    private var total: Double { max(deep + rem + core, 0.0001) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 1) {
                seg(CB.bone, deep, w)
                seg(CB.gray300, core, w)
                seg(CB.gray500, rem, w)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: CBRadius.sm))
    }
    private func seg(_ color: Color, _ v: Double, _ w: CGFloat) -> some View {
        color.frame(width: max(0, w * CGFloat(v / total)))
    }
}

// HOY = tríada (I5 §2): COMER · ENTRENAR · DORMIR en 3 columnas de igual jerarquía,
// + chip de recovery_state debajo. Inputs planos (sin VM) → showcaseable en la galería.
struct TodayTriad: View {
    struct Eat { var kcalConsumed: Double; var kcalTarget: Double }
    struct Train { var name: String; var isRest: Bool; var completed: Bool; var exerciseCount: Int }
    struct Sleep { var hours: Double?; var deep: Double?; var rem: Double?; var core: Double? }

    let eat: Eat
    let train: Train?
    let sleep: Sleep
    let recoveryState: String
    var onEat: () -> Void = {}
    var onTrain: () -> Void = {}
    var onSleep: () -> Void = {}

    var body: some View {
        VStack(spacing: CBSpace.s3) {
            HStack(spacing: CBSpace.s3) {
                column("COMER", tap: onEat) { eatContent }
                column("ENTRENAR", tap: onTrain) { trainContent }
                column("DORMIR", tap: onSleep) { sleepContent }
            }
            .fixedSize(horizontal: false, vertical: true)
            RecoveryChip(state: recoveryState)
        }
    }

    @ViewBuilder private func column(_ title: String, tap: @escaping () -> Void,
                                     @ViewBuilder _ content: () -> some View) -> some View {
        Button(action: tap) {
            VStack(spacing: CBSpace.s2) {
                Text(title).cbLabel(color: CB.textSecondary)
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .cbCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // COMER: anillo compacto de kcal + % del objetivo.
    private var eatContent: some View {
        let frac = eat.kcalTarget > 0 ? eat.kcalConsumed / eat.kcalTarget : 0
        let over = eat.kcalConsumed > eat.kcalTarget && eat.kcalTarget > 0
        return VStack(spacing: 4) {
            ZStack {
                Circle().stroke(CB.surfaceInput, lineWidth: 6)
                Circle().trim(from: 0, to: min(1, frac))
                    .stroke(over ? CB.alert : CB.bone, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(CBNumber.format(eat.kcalConsumed, decimals: 0))
                    .cbNumber(18, color: over ? CB.alert : CB.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: 60, height: 60)
            Text("\(CBNumber.percent(frac)) del objetivo").font(CBFont.caption).foregroundStyle(CB.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // ENTRENAR: descanso / completado / sesión del día.
    @ViewBuilder private var trainContent: some View {
        if let t = train {
            if t.isRest {
                VStack(spacing: 6) {
                    CBIcon(name: .today, size: 30, color: CB.textTertiary)
                    Text("Descanso").font(CBFont.bodySemibold).foregroundStyle(CB.textSecondary)
                }
            } else if t.completed {
                VStack(spacing: 6) {
                    CBIcon(name: .check, size: 30, color: CB.success)
                    Text(t.name).font(CBFont.bodySM).foregroundStyle(CB.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                }
            } else {
                VStack(spacing: 4) {
                    CBIcon(name: .dumbbell, size: 28, color: CB.bone)
                    Text(t.name).font(CBFont.bodySM).foregroundStyle(CB.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(t.exerciseCount) ejerc.").font(CBFont.caption).foregroundStyle(CB.textTertiary)
                }
            }
        } else {
            Text("—").cbNumber(24, color: CB.textTertiary)
        }
    }

    // DORMIR: horas de anoche + mini-barra de fases (o sin datos).
    @ViewBuilder private var sleepContent: some View {
        if let h = sleep.hours {
            VStack(spacing: 6) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(CBNumber.format(h, decimals: 1)).cbNumber(26, color: CB.bone).lineLimit(1).minimumScaleFactor(0.6)
                    Text("h").font(CBFont.bodySM).foregroundStyle(CB.textSecondary)
                }
                if let d = sleep.deep, let r = sleep.rem, let c = sleep.core {
                    SleepMiniBar(deep: d, rem: r, core: c).padding(.horizontal, 2)
                }
            }
        } else {
            VStack(spacing: 6) {
                CBIcon(name: .clock, size: 26, color: CB.textTertiary)
                Text("sin datos").font(CBFont.caption).foregroundStyle(CB.textTertiary)
            }
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        TodayTriad(
            eat: .init(kcalConsumed: 1830, kcalTarget: 2650),
            train: .init(name: "Upper A", isRest: false, completed: false, exerciseCount: 6),
            sleep: .init(hours: 6.95, deep: 1.2, rem: 1.55, core: 4.2),
            recoveryState: "caution")
        RecoveryChip(state: "low")
        RecoveryChip(state: "good")
        RecoveryChip(state: "no_data")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CB.bgApp)
    .preferredColorScheme(.dark)
}
