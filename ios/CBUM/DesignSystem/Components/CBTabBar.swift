import SwiftUI

// Las 5 secciones de CBUM.
enum CBTab: String, CaseIterable, Identifiable {
    case hoy, entreno, nutricion, progreso, ajustes
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hoy: return "Hoy"
        case .entreno: return "Entreno"
        case .nutricion: return "Nutrición"
        case .progreso: return "Progreso"
        case .ajustes: return "Ajustes"
        }
    }

    var icon: CBIconName {
        switch self {
        case .hoy: return .today
        case .entreno: return .dumbbell
        case .nutricion: return .meal
        case .progreso: return .progress
        case .ajustes: return .settings
        }
    }
}

// Componente 1a — Tab bar inferior. Activo = bone, inactivo = tenue.
struct CBTabBar: View {
    @Binding var active: CBTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CBTab.allCases) { tab in
                let isActive = tab == active
                Button {
                    withAnimation(CBMotion.tap) { active = tab }
                } label: {
                    VStack(spacing: 4) {
                        CBIcon(name: tab.icon, size: 24,
                               color: isActive ? CB.accent : CB.textTertiary)
                        Text(tab.title)
                            .font(CBFont.labelSmall)
                            .tracking(CBFont.Size.labelSM * CBFont.labelTrackFactor)
                            .textCase(.uppercase)
                            .foregroundStyle(isActive ? CB.accent : CB.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.top, CBSpace.s2)
        .padding(.bottom, CBSpace.s2)
        .frame(height: CBSpace.tabBar, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(
            CB.surfaceRaised
                .overlay(alignment: .top) {
                    Rectangle().fill(CB.borderDefault).frame(height: CBRadius.borderHair)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// Componente 1b — Header de pantalla: eyebrow mono opcional, título
// display uppercase, back opcional y una acción trailing.
struct CBHeader: View {
    let title: String
    var eyebrow: String? = nil
    var large: Bool = true
    var onBack: (() -> Void)? = nil
    var actionIcon: CBIconName? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: CBSpace.s3) {
            if let onBack {
                Button(action: onBack) {
                    CBIcon(name: .chevronL, size: 26, color: CB.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Volver")
            }

            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(CBFont.mono(CBFont.Size.label))
                        .tracking(CBFont.Size.label * CBFont.labelTrackFactor)
                        .textCase(.uppercase)
                        .foregroundStyle(CB.textSecondary)
                }
                Text(title)
                    .cbDisplay(large ? CBFont.Size.displayMD : CBFont.Size.displaySM)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer(minLength: 0)

            if let actionIcon, let action {
                Button(action: action) {
                    CBIcon(name: actionIcon, size: 24, color: CB.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CBSpace.gutterScreen)
        .padding(.vertical, CBSpace.s3)
    }
}

#Preview("TabBar + Header") {
    struct Demo: View {
        @State var tab: CBTab = .hoy
        var body: some View {
            VStack(spacing: 0) {
                CBHeader(title: "Hoy", eyebrow: "Lun · 14 Jul", actionIcon: .settings, action: {})
                CBHeader(title: "Press banca", large: false, onBack: {})
                Spacer()
                CBTabBar(active: $tab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CB.bgApp)
        }
    }
    return Demo().preferredColorScheme(.dark)
}
