import SwiftUI

// Componente 9 — Badge de fuente/confianza.
// ⚖ PESADO / 🏷 ETIQUETA / 📷 ESTIMADO (glifos scale/tag/camera del design).
// Variante lowConfidence (confidence < 0.7) en color estimated.
struct SourceBadge: View {
    enum Kind { case weighed, label, estimated }

    let kind: Kind
    var lowConfidence: Bool = false
    var showLabel: Bool = true

    // Deriva el badge desde los campos del contrato (source + portion_basis + confidence).
    init(source: String, portionBasis: String, confidence: Double, showLabel: Bool = true) {
        self.showLabel = showLabel
        self.lowConfidence = confidence < 0.7
        if source == "photo" || portionBasis == "estimated" {
            self.kind = .estimated
        } else if source == "label" || source == "barcode" {
            self.kind = portionBasis == "weighed" ? .weighed : .label
        } else {
            self.kind = portionBasis == "weighed" ? .weighed : .estimated
        }
    }

    init(kind: Kind, lowConfidence: Bool = false, showLabel: Bool = true) {
        self.kind = kind
        self.lowConfidence = lowConfidence
        self.showLabel = showLabel
    }

    private var icon: CBIconName {
        switch kind {
        case .weighed: return .scale
        case .label: return .tag
        case .estimated: return .camera
        }
    }
    private var text: String {
        switch kind {
        case .weighed: return "PESADO"
        case .label: return "ETIQUETA"
        case .estimated: return "ESTIMADO"
        }
    }
    private var tint: Color {
        (kind == .estimated || lowConfidence) ? CB.estimated : CB.textSecondary
    }

    var body: some View {
        HStack(spacing: 4) {
            CBIcon(name: icon, size: 13, color: tint)
            if showLabel {
                Text(text)
                    .font(CBFont.labelSmall)
                    .tracking(CBFont.Size.labelSM * CBFont.labelTrackFactor)
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .overlay(
            RoundedRectangle(cornerRadius: CBRadius.sm)
                .strokeBorder(tint.opacity(lowConfidence ? 1 : 0.4),
                              lineWidth: CBRadius.borderHair)
        )
        .accessibilityLabel("Fuente \(text)\(lowConfidence ? ", baja confianza" : "")")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 12) {
            SourceBadge(kind: .weighed)
            SourceBadge(kind: .label)
            SourceBadge(kind: .estimated)
        }
        HStack(spacing: 12) {
            SourceBadge(source: "photo", portionBasis: "estimated", confidence: 0.55)
            SourceBadge(source: "label", portionBasis: "weighed", confidence: 0.98)
            SourceBadge(kind: .estimated, showLabel: false)
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(CB.bgApp)
    .preferredColorScheme(.dark)
}
