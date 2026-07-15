import SwiftUI

// Componente 2 — Botón de acción CBUM.
// Display uppercase condensado, bordes duros, press seco (scale 0.97).
// primary = CTA bone; secondary = outline; destructive = outline rojo.
struct CBButton: View {
    enum Style { case primary, secondary, destructive }
    enum Size { case lg, md, sm }

    let title: String
    var style: Style = .primary
    var size: Size = .lg
    var icon: CBIconName? = nil
    var iconRight: CBIconName? = nil
    var fullWidth: Bool = true
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var pressed = false

    private var height: CGFloat {
        switch size {
        case .lg: return CBSpace.touchLG   // 56
        case .md: return 48
        case .sm: return CBSpace.touch     // 44
        }
    }

    private var fontSize: CGFloat {
        switch size {
        case .lg: return 20
        case .md: return 17
        case .sm: return 14
        }
    }

    private var fillColor: Color {
        switch style {
        case .primary: return CB.accent
        case .secondary, .destructive: return .clear
        }
    }

    private var strokeColor: Color {
        switch style {
        case .primary: return .clear
        case .secondary: return CB.borderAccent
        case .destructive: return CB.danger
        }
    }

    private var labelColor: Color {
        switch style {
        case .primary: return CB.textOnAccent
        case .secondary: return CB.textAccent
        case .destructive: return CB.danger
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: CBSpace.s2) {
                if let icon { CBIcon(name: icon, size: fontSize + 4, color: labelColor) }
                Text(title)
                    .font(CBFont.display(fontSize))
                    .tracking(fontSize * CBFont.displayTrackFactor)
                    .textCase(.uppercase)
                if let iconRight { CBIcon(name: iconRight, size: fontSize + 4, color: labelColor) }
            }
            .foregroundStyle(labelColor)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, fullWidth ? 0 : CBSpace.s5)
            .background(fillColor, in: RoundedRectangle(cornerRadius: CBRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CBRadius.md, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: style == .primary ? 0 : CBRadius.borderThick)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .scaleEffect(pressed ? CBMotion.pressScale : 1)
        .animation(CBMotion.tap, value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if isEnabled { pressed = true } }
                .onEnded { _ in pressed = false }
        )
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    VStack(spacing: CBSpace.s4) {
        CBButton(title: "Empezar entreno", style: .primary, size: .lg, icon: .dumbbell) {}
        CBButton(title: "Sustituir", style: .secondary, size: .md, iconRight: .swap) {}
        CBButton(title: "Descartar", style: .destructive, size: .sm, fullWidth: false) {}
        CBButton(title: "Deshabilitado", style: .primary, isEnabled: false) {}
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CB.bgApp)
    .preferredColorScheme(.dark)
}
