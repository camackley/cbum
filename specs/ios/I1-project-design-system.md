# I1 — Proyecto Xcode + design system (Agente B)

**Prerrequisito:** leer `specs/00-overview.md`, `specs/01-contracts.md` y `design-brief.md`.

## Proyecto
- App SwiftUI **CBUM**, iOS 17+, solo iPhone, solo portrait, **dark mode forzado** (`.preferredColorScheme(.dark)`).
- Bundle id `com.mackley.cbum`. Firma: Personal Team (automática) — no requiere cuenta paga. Capability **HealthKit** (soportada en free tier). `Info.plist`: `NSHealthShareUsageDescription` y `NSHealthUpdateUsageDescription` en español.
- Estructura: `CBUM/App`, `DesignSystem/`, `Models/`, `Services/` (API, Sync, HealthKit), `Features/` (Today, Session, Nutrition, Progress, Settings).
- Sin dependencias externas; Swift Charts (nativo) para gráficos.

## Tokens (`DesignSystem/Theme.swift`)
```swift
enum CB {
  static let black = Color(hex: 0x000000)        // fondo base
  static let bone  = Color(hex: 0xF5F5DC)        // acento: CTAs, números clave, líneas de gráfico
  static let surface = Color(hex: 0x111111)      // cards
  static let border  = Color(hex: 0x2A2A2A)
  static let textPrimary = Color(hex: 0xF5F5DC)
  static let textSecondary = Color(hex: 0x8A8A80) // gris cálido derivado del beige
  static let success = Color(hex: 0x86EFAC)       // PRs, on-track
  static let alert   = Color(hex: 0xF87171)       // fallos, off-track
  static let estimated = Color(hex: 0xD4B85A)     // datos estimados / baja confianza
}
```
Si el usuario entrega un design system generado desde `design-brief.md`, sus valores reemplazan estos defaults (solo cambiar `Theme.swift`).

**Tipografía:** display = system SF Pro, `.fontWidth(.condensed)`, weight `.black`, UPPERCASE, tracking −0.5 para títulos y números protagonistas. Helpers: `CBFont.display(_ size:)` (títulos 28–34), `CBFont.number(_ size:)` (números gigantes 40–64, monospacedDigit), `CBFont.body` (17 regular), `CBFont.caption` (13). Radios: 4pt (duros). Espaciado: grid 4pt. Animaciones: 0.15s easeOut, sin bounce; excepción: celebración de PR (0.4s spring + haptic `.success`).

## Los 12 componentes (`DesignSystem/Components/`) — construir TODOS con Preview
1. `CBTabBar` + `CBHeader` — 5 tabs (Hoy, Entreno, Nutrición, Progreso, Ajustes); header con título display uppercase.
2. `CBButton` — estilos `.primary` (fondo bone, texto negro, uppercase), `.secondary` (borde bone), `.destructive`; altura 56pt; pressed = escala 0.97.
3. `MacroRings` — anillo kcal exterior + 3 barras P/C/G; números al centro (`CBFont.number`); color bone, excedido → alert.
4. `StatCard` — valor grande + label uppercase + delta con flecha; variante badge "CALIBRANDO" (estimated).
5. `ExerciseCard` — nombre, prescripción "4×6–8 @ RIR 2", peso sugerido destacado, `last_session` en secundario, botón sustituir.
6. `SetLoggerRow` — **el componente estrella**: steppers grandes de peso (± increment_kg del ejercicio) y reps (±1), `RIRSelector`, botón guardar 56pt alcanzable con pulgar. Estados: pendiente (borde), guardado (fondo surface + check), PR (borde success + flash). Targets táctiles ≥ 48pt (manos sudadas).
7. `RIRSelector` — segmented 0–5, un tap, seleccionado = fondo bone/texto negro.
8. `RestTimer` — countdown `CBFont.number` 64pt, barra de progreso, botones +30s / saltar; al llegar a 0: haptic + sonido corto.
9. `SourceBadge` — ⚖️ PESADO / 🏷 ETIQUETA / 📷 ESTIMADO; variante `lowConfidence` (confidence < 0.7) en color estimated.
10. `MealRow` — nombre, hora, kcal + P/C/G, `SourceBadge`, tap → editar.
11. `TrendChart` — Swift Charts: línea bone sobre negro, puntos de PR marcados, eje mínimo; acepta serie `[(date, value)]`.
12. `VolumeBars` — barras horizontales por grupo muscular con banda de rango objetivo (10–20) visible; dentro → bone, fuera → estimated.

## Aceptación
- Compila sin warnings; catálogo de previews (`ComponentGallery.swift`) mostrando los 12 componentes con datos realistas de gym.
- Todo texto/color viene de `Theme`/`CBFont` — cero literales sueltos en features.
