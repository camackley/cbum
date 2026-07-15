import SwiftUI

// ============================================================
// CBUM · DESIGN TOKENS
// Fuente de verdad: proyecto "CBUM Design System" (claude.ai/design)
// importado vía el MCP de diseño. Estos valores reemplazan los
// defaults de fallback listados en la spec I1. Nada de valores
// visuales hardcodeados en features: todo sale de aquí.
// ============================================================

// MARK: - Color palette

/// `CB` expone la paleta y los alias semánticos del design system.
/// Los nombres de I1 (black, bone, surface, border, textPrimary,
/// textSecondary, success, alert, estimated) se conservan como alias
/// para no romper referencias; el resto son los semánticos oficiales.
enum CB {
    // --- Base raw palette ---
    static let black    = Color(hex: 0x000000) // bg-app · negro puro
    static let bone     = Color(hex: 0xF5F5DC) // acento · beige hueso

    // Neutral surfaces (warm-leaning grays)
    static let gray950  = Color(hex: 0x0A0A0A) // raised background
    static let gray900  = Color(hex: 0x121211) // card surface
    static let gray850  = Color(hex: 0x1A1A18) // input surface
    static let gray800  = Color(hex: 0x232320) // pressed surface / subtle border
    static let gray700  = Color(hex: 0x33332E) // default border, dividers
    static let gray600  = Color(hex: 0x4A4A43) // strong border
    static let gray500  = Color(hex: 0x6E6E64) // disabled / tertiary text
    static let gray400  = Color(hex: 0x9A968C) // secondary text (warm)
    static let gray300  = Color(hex: 0xC7C4B8) // high-emphasis muted
    static let white    = Color(hex: 0xF2F1EA) // warm white · primary text

    // Chromatic semantics (surgical use)
    static let greenPR    = Color(hex: 0xB6F03C) // PR / success / on-track · acid lime
    static let greenPRDim = Color(hex: 0x7FA82A)
    static let redAlert   = Color(hex: 0xFF4A3D) // danger / miss / off-track
    static let redAlertDim = Color(hex: 0xB8342B)
    static let amberEst   = Color(hex: 0xD6A63C) // estimated / low confidence
    static let amberEstDim = Color(hex: 0x8F6E27)

    // Accent scale
    static let boneDim   = Color(hex: 0xD8D8BE)
    static let bonePress = Color(hex: 0xBEBEA2)

    // ---- Semantic aliases (referenciar estos en componentes) ----
    // Backgrounds & surfaces
    static let bgApp          = black
    static let surfaceRaised  = gray950
    static let surfaceCard    = gray900
    static let surfaceInput   = gray850
    static let surfacePressed = gray800

    // Borders
    static let borderSubtle  = gray800
    static let borderDefault = gray700
    static let borderStrong  = gray600
    static let borderAccent  = bone

    // Text
    static let textPrimary   = white
    static let textSecondary = gray400
    static let textTertiary  = gray500
    static let textAccent    = bone
    static let textOnAccent  = black

    // Interactive / accent
    static let accent      = bone
    static let accentHover = boneDim
    static let accentPress = bonePress

    // Status
    static let success   = greenPR   // alias I1
    static let alert     = redAlert  // alias I1
    static let estimated = amberEst  // alias I1
    static let danger    = redAlert

    // Data-quality confidence
    static let confidenceHigh = white     // weighed / verified
    static let confidenceMid  = gray400   // label / packaged
    static let confidenceLow  = amberEst  // photo estimate

    // Alias I1 kept for compatibility
    static let surface = surfaceCard
    static let border  = borderDefault
}

// MARK: - Typography

/// Escala tipográfica oficial. Display/Data usan SF Pro condensada
/// (equivalente iOS-nativo de Barlow Condensed, que el propio design
/// declara como fallback); Body/Mono usan SF Pro Text / SF Mono.
/// Sin fuentes vendidas → cero dependencias externas (ver DECISIONS.md).
enum CBFont {
    // Named sizes (tokens)
    enum Size {
        // Display
        static let displayXL: CGFloat = 56
        static let displayLG: CGFloat = 40
        static let displayMD: CGFloat = 30
        static let displaySM: CGFloat = 22
        // Data (big protagonist numbers)
        static let dataXL: CGFloat = 96
        static let dataLG: CGFloat = 64
        static let dataMD: CGFloat = 40
        static let dataSM: CGFloat = 28
        // Body
        static let bodyLG: CGFloat = 18
        static let body: CGFloat = 16
        static let bodySM: CGFloat = 14
        static let bodyXS: CGFloat = 12
        // Label / mono
        static let label: CGFloat = 12
        static let labelSM: CGFloat = 10
    }

    // Tracking (as fraction of size, matching the CSS em values)
    static let displayTrackFactor: CGFloat = -0.01
    static let dataTrackFactor: CGFloat = -0.02
    static let labelTrackFactor: CGFloat = 0.12
    static let labelLooseTrackFactor: CGFloat = 0.18

    // ---- Font builders ----

    /// Títulos display: condensada, ultra-bold. Rango típico 22–56.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed)
    }

    /// Números protagonistas: condensada, black, dígitos monoespaciados. 28–96.
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed).monospacedDigit()
    }

    /// Cuerpo de texto legible.
    static var body: Font { .system(size: Size.body, weight: .regular) }
    static var bodySM: Font { .system(size: Size.bodySM, weight: .regular) }   // 14
    static var bodyLarge: Font { .system(size: Size.bodyLG, weight: .regular) }
    static var bodyMedium: Font { .system(size: Size.body, weight: .medium) }
    static var bodySemibold: Font { .system(size: Size.body, weight: .semibold) }
    static var caption: Font { .system(size: Size.bodyXS, weight: .regular) }
    static var captionSmall: Font { .system(size: Size.bodySM, weight: .regular) }

    /// Label uppercase tracked (semibold, condensada opcional).
    static var label: Font { .system(size: Size.label, weight: .semibold) }
    static var labelSmall: Font { .system(size: Size.labelSM, weight: .semibold) }

    /// Mono técnico (badges de fuente, valores técnicos).
    static func mono(_ size: CGFloat = Size.label) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

// MARK: - Spacing (strict 4pt grid)

enum CBSpace {
    static let s0: CGFloat = 0
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s7: CGFloat = 28
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
    static let s12: CGFloat = 48
    static let s14: CGFloat = 56
    static let s16: CGFloat = 64
    static let s20: CGFloat = 80

    // Component-level rhythm
    static let gutterScreen: CGFloat = s5 // 20 · padding horizontal de pantalla
    static let gapCard: CGFloat = s4       // 16 · dentro de cards
    static let gapStack: CGFloat = s3      // 12 · gap vertical de listas

    // iOS chrome heights
    static let tabBar: CGFloat = 84   // incl. home indicator
    static let header: CGFloat = 52
    static let touch: CGFloat = 44    // hit target mínimo
    static let touchLG: CGFloat = 56  // CTA primario
}

// MARK: - Radii, borders

enum CBRadius {
    static let none: CGFloat = 0
    static let sm: CGFloat = 2   // chips, badges, inputs
    static let md: CGFloat = 4   // cards, buttons
    static let lg: CGFloat = 8   // sheets, containers grandes (máx)
    static let pill: CGFloat = 999

    static let borderHair: CGFloat = 1
    static let borderThick: CGFloat = 2
}

// MARK: - Motion

enum CBMotion {
    // Durations (segundos)
    static let instant: Double = 0.08
    static let fast: Double = 0.12
    static let base: Double = 0.18
    static let slow: Double = 0.26

    static let pressScale: CGFloat = 0.97

    // Easings (short, dry, decisive — no bounce salvo PR)
    static var easeOut: Animation { .timingCurve(0.2, 0, 0, 1, duration: base) }
    static var tap: Animation { .timingCurve(0.2, 0, 0, 1, duration: fast) }
    static var sheet: Animation { .timingCurve(0.2, 0, 0, 1, duration: slow) }
    /// Única excepción con overshoot: celebración de PR (0.4s spring).
    static var pr: Animation { .spring(response: 0.4, dampingFraction: 0.62) }
}

// MARK: - View helpers

extension View {
    /// Título display uppercase con tracking apretado.
    func cbDisplay(_ size: CGFloat = CBFont.Size.displayMD, color: Color = CB.textPrimary) -> some View {
        self.font(CBFont.display(size))
            .tracking(size * CBFont.displayTrackFactor)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Número protagonista (monoespaciado, condensado).
    func cbNumber(_ size: CGFloat = CBFont.Size.dataMD, color: Color = CB.textPrimary) -> some View {
        self.font(CBFont.number(size))
            .tracking(size * CBFont.dataTrackFactor)
            .foregroundStyle(color)
    }

    /// Label uppercase tracked.
    func cbLabel(color: Color = CB.textSecondary, loose: Bool = false) -> some View {
        self.font(CBFont.label)
            .tracking(CBFont.Size.label * (loose ? CBFont.labelLooseTrackFactor : CBFont.labelTrackFactor))
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Superficie de card estándar (surface + hairline border + radio duro).
    func cbCard(padding: CGFloat = CBSpace.gapCard,
                fill: Color = CB.surfaceCard,
                stroke: Color = CB.borderDefault,
                radius: CGFloat = CBRadius.md) -> some View {
        self.padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: CBRadius.borderHair)
            )
    }
}
