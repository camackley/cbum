import SwiftUI

// Extra — Toast de celebración de PR. Verde, trofeo, un único "punch" de
// entrada (la sola excepción de overshoot en CBUM). Haptic .success lo
// dispara quien lo presenta.
struct PRToast: View {
    let exercise: String
    let detail: String            // "e1RM 102.5 kg · +2.5 vs anterior"
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: CBSpace.s3) {
            CBIcon(name: .trophy, size: 28, color: CB.textOnAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("¡PR! \(exercise)")
                    .font(CBFont.display(20)).textCase(.uppercase)
                    .foregroundStyle(CB.textOnAccent)
                Text(detail).font(CBFont.bodySM).foregroundStyle(CB.textOnAccent.opacity(0.8))
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    CBIcon(name: .x, size: 20, color: CB.textOnAccent.opacity(0.7))
                }.buttonStyle(.plain)
            }
        }
        .padding(CBSpace.s4)
        .background(CB.success, in: RoundedRectangle(cornerRadius: CBRadius.md))
        .shadow(color: .black.opacity(0.6), radius: 24, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nuevo récord personal en \(exercise). \(detail)")
    }
}

// Modificador para presentarlo con el punch de entrada + auto-dismiss.
extension View {
    func prToast(item: Binding<PRToastData?>) -> some View {
        overlay(alignment: .top) {
            if let data = item.wrappedValue {
                PRToast(exercise: data.exercise, detail: data.detail) {
                    withAnimation(CBMotion.easeOut) { item.wrappedValue = nil }
                }
                .padding(.horizontal, CBSpace.gutterScreen)
                .padding(.top, CBSpace.s2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(CBMotion.pr, value: item.wrappedValue?.id)
    }
}

struct PRToastData: Identifiable, Equatable {
    let id = UUID()
    let exercise: String
    let detail: String
}

#Preview {
    PRToast(exercise: "Press banca", detail: "e1RM 102.5 kg · +2.5 vs anterior", onDismiss: {})
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CB.bgApp)
        .preferredColorScheme(.dark)
}
