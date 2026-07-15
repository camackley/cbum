# CBUM — App iOS (Agente B)

App SwiftUI de coaching de gym y nutrición. iOS 17+, dark mode forzado, solo
iPhone/portrait, sin dependencias externas. Fuente de verdad de datos/fórmulas:
`../specs/01-contracts.md`.

## Abrir y correr
```bash
open CBUM.xcodeproj      # Xcode 15+
```
1. Selecciona el target **CBUM** y un simulador iPhone (o tu iPhone con Personal Team).
2. En **Signing & Capabilities** fija tu *Personal Team* (firma automática). La
   capability **HealthKit** ya está declarada (entitlements + Info.plist).
3. Run (⌘R). Arranca contra el **mock local** (datos semilla realistas) — no
   necesitas backend para explorar toda la app.

### Conectar el backend real
Ajustes → apagar "Usar mock local" → poner **Base URL** (`https://…workers.dev`) y
**API Token** (se guarda en Keychain) → "Probar conexión". El intercambio
mock/live es en caliente (`AppEnvironment.switchClient`).

## Tests
`⌘U` corre `CBUMTests` (target de unit-test). `FormulasKitTests` valida los test
vectors EXACTOS de contracts §5 (EMA 80.14, e1RM 133.3, sugerencia 82.5, TDEE 2720).

## Estructura
```
CBUM/
  App/            CBUMApp, RootView, Router, AppEnvironment
  DesignSystem/   Theme (tokens del design MCP), Components/ (12 + extras), ComponentGallery
  Models/         @Model SwiftData (contracts §1) + enums + DTO converters
  Services/       FormulasKit (§5), APIClient (Live + Mock), SyncEngine (outbox), HealthKitService, AppConfig
  Features/       Today, Session, Nutrition, Progress, Settings
  Resources/      Info.plist, entitlements, Assets.xcassets
CBUMTests/        FormulasKitTests
```

## Regenerar el proyecto
El `.xcodeproj` se versiona. Si tienes [XcodeGen](https://github.com/yonaskolb/XcodeGen):
`xcodegen generate` lo reconstruye desde `project.yml` (fuente reproducible).

## Arquitectura (resumen)
- **Offline-first:** todo write va a SwiftData (UI instantánea) + `Outbox` (cola FIFO
  idempotente por UUID de cliente). El `SyncEngine` drena con backoff y hace pull
  incremental (`/api/changes`); el server siempre gana en conflicto.
- **Precisión:** e1RM solo dentro del rango de validez, peso como tendencia EMA, RIR
  obligatorio por set (sin preselección), fórmulas duplicadas y testeadas en
  `FormulasKit` (mismos números que el server).
- **HealthKit:** escribe comida/entreno, lee peso/pasos/sueño/kcal activas (mapeo §7).
- **Fotos de comida:** NO se capturan en la app (viven en el chat de Claude); la app
  muestra, edita y sincroniza lo logueado.

Decisiones y checklist de integración: `../DECISIONS.md`.
