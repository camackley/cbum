import SwiftUI

// Componente foundation: set curado de glifos (equivalente nativo de la
// familia Lucide-outline del design system) mapeados a SF Symbols.
// Nombres tomados de foundation/Icon del proyecto de diseño.
enum CBIconName: String {
    case today, dumbbell, meal, progress, settings
    case plus, minus, check, x
    case chevronR, chevronL, chevronD
    case edit, swap, scale, tag, camera, timer, trophy, flame, zap
    case arrowDown, arrowUp, clock

    var systemName: String {
        switch self {
        case .today:    return "sun.max"
        case .dumbbell: return "dumbbell"
        case .meal:     return "fork.knife"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .settings: return "gearshape"
        case .plus:     return "plus"
        case .minus:    return "minus"
        case .check:    return "checkmark"
        case .x:        return "xmark"
        case .chevronR: return "chevron.right"
        case .chevronL: return "chevron.left"
        case .chevronD: return "chevron.down"
        case .edit:     return "pencil"
        case .swap:     return "arrow.left.arrow.right"
        case .scale:    return "scalemass"
        case .tag:      return "tag"
        case .camera:   return "camera"
        case .timer:    return "timer"
        case .trophy:   return "trophy"
        case .flame:    return "flame"
        case .zap:      return "bolt"
        case .arrowDown: return "arrow.down"
        case .arrowUp:   return "arrow.up"
        case .clock:    return "clock"
        }
    }
}

struct CBIcon: View {
    let name: CBIconName
    var size: CGFloat = 24
    var color: Color = CB.textPrimary

    var body: some View {
        Image(systemName: name.systemName)
            .font(.system(size: size * 0.82, weight: .semibold)) // stroke ~1.75px feel
            .foregroundStyle(color)
            .frame(width: size, height: size)
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 20) {
            ForEach([CBIconName.today, .dumbbell, .meal, .progress, .settings,
                     .plus, .minus, .check, .x, .chevronR,
                     .chevronL, .chevronD, .edit, .swap, .scale,
                     .tag, .camera, .timer, .trophy, .flame,
                     .zap, .arrowDown, .arrowUp, .clock], id: \.rawValue) { icon in
                VStack(spacing: 6) {
                    CBIcon(name: icon, color: CB.bone)
                    Text(icon.rawValue).font(.system(size: 9)).foregroundStyle(CB.textSecondary)
                }
            }
        }
        .padding()
    }
    .background(CB.bgApp)
    .preferredColorScheme(.dark)
}
