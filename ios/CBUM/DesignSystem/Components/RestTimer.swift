import SwiftUI

// Componente 8 — Rest timer. Countdown gigante (tabular), anillo de progreso
// bone; arranca solo al guardar set. +30s extiende, Saltar salta. Al llegar
// a 0: haptic + verde. Usable con el teléfono en el piso.
struct RestTimer: View {
    let duration: Int                 // segundos totales
    @Binding var remaining: Int       // segundos restantes (controlado por el padre)
    var compact: Bool = false
    var onAddThirty: () -> Void
    var onSkip: () -> Void

    private var progress: Double {
        // Clamp 0...1: +30s puede dejar remaining > duration (progress negativo
        // producía "Invalid frame dimension" en la barra compacta).
        guard duration > 0 else { return 1 }
        return min(1, max(0, Double(duration - remaining) / Double(duration)))
    }
    private var done: Bool { remaining <= 0 }

    private var clock: String {
        let m = max(0, remaining) / 60
        let s = max(0, remaining) % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        if compact { compactBar } else { full }
    }

    private var full: some View {
        VStack(spacing: CBSpace.s5) {
            ZStack {
                Circle().stroke(CB.surfaceInput, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(done ? CB.success : CB.bone,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: remaining)
                VStack(spacing: 0) {
                    Text("DESCANSO").cbLabel()
                    Text(clock).cbNumber(CBFont.Size.dataLG, color: done ? CB.success : CB.textPrimary)
                }
            }
            .frame(width: 240, height: 240)

            HStack(spacing: CBSpace.s3) {
                CBButton(title: "+30s", style: .secondary, size: .md) { onAddThirty() }
                CBButton(title: "Saltar", style: .secondary, size: .md, iconRight: .chevronR) { onSkip() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Temporizador de descanso")
        .accessibilityValue(done ? "Completo" : "\(clock) restantes")
    }

    // Barra flotante inferior mientras corre (no bloquea loguear otro set).
    private var compactBar: some View {
        HStack(spacing: CBSpace.s3) {
            CBIcon(name: .timer, size: 22, color: done ? CB.success : CB.bone)
            Text(clock).cbNumber(28, color: done ? CB.success : CB.textPrimary)
            Text("descanso").font(CBFont.caption).foregroundStyle(CB.textSecondary)
            Spacer()
            Button { onAddThirty() } label: {
                Text("+30s").font(CBFont.bodySemibold).foregroundStyle(CB.bone)
            }.buttonStyle(.plain)
            Button { onSkip() } label: {
                Text("Saltar").font(CBFont.bodySemibold).foregroundStyle(CB.textSecondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, CBSpace.s4)
        .frame(height: CBSpace.touchLG)
        .background(CB.surfaceRaised, in: RoundedRectangle(cornerRadius: CBRadius.md))
        .overlay(RoundedRectangle(cornerRadius: CBRadius.md).strokeBorder(done ? CB.success : CB.borderStrong, lineWidth: CBRadius.borderHair))
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Rectangle().fill(done ? CB.success : CB.bone)
                    .frame(width: geo.size.width * progress, height: 2)
            }
        }
    }
}

#Preview {
    struct Demo: View {
        @State var r1 = 92
        @State var r2 = 0
        @State var r3 = 45
        var body: some View {
            VStack(spacing: 32) {
                RestTimer(duration: 150, remaining: $r1, onAddThirty: { r1 += 30 }, onSkip: { r1 = 0 })
                RestTimer(duration: 150, remaining: $r2, onAddThirty: { r2 += 30 }, onSkip: {})
                RestTimer(duration: 180, remaining: $r3, compact: true, onAddThirty: { r3 += 30 }, onSkip: { r3 = 0 })
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CB.bgApp)
        }
    }
    return Demo().preferredColorScheme(.dark)
}
