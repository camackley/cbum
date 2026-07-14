# CBUM — Overview para agentes constructores

Lee este archivo y `01-contracts.md` COMPLETOS antes de escribir código. `01-contracts.md` es la **única fuente de verdad** para schemas, API y fórmulas; si algo aquí o en PLAN.md contradice a contracts, gana contracts.

## Qué se construye

App personal (un solo usuario) de coaching de gym y nutrición:

- **Agente A — `backend/`**: Cloudflare Workers (TypeScript + Hono) + D1. Expone (1) REST API para la app iOS y (2) servidor MCP remoto para que Claude actúe como coach. Specs: `backend/B1` → `B4`, en orden.
- **Agente B — `ios/`**: App SwiftUI (iOS 17+) llamada **CBUM**. Logging de entrenos, dashboards, sync con el backend y con Apple Health. Specs: `ios/I1` → `I4`, en orden.

Los dos agentes trabajan en paralelo contra `01-contracts.md`. No cambies un contrato sin actualizar `01-contracts.md` y anotarlo en `DECISIONS.md` (créalo si no existe).

## Principio rector: PRECISIÓN (MUST)

1. **Nunca inventar macros.** Todo alimento se resuelve contra USDA FoodData Central u Open Food Facts, o viene de etiqueta/manual. Cada meal registra `source`, `confidence`, `portion_basis`.
2. **TDEE adaptativo**, calculado de ingesta real vs tendencia de peso (EMA). Nunca de fórmulas estáticas (solo como fallback marcado `calibrating`) y **nunca** de las calorías del wearable.
3. **Peso = tendencia EMA**, jamás decisiones sobre lecturas crudas.
4. **Esfuerzo = RIR** por set; **fuerza = e1RM** solo dentro del rango de validez de la fórmula.
5. Fórmulas exactas y test vectors numéricos en `01-contracts.md` §5 — los tests DEBEN pasar con esos valores.

## Convenciones compartidas

| Tema | Regla |
|---|---|
| Unidades | kg, gramos, kcal. Nunca lb ni oz. |
| Timestamps | ISO-8601 con offset (`2026-07-14T18:30:00-05:00`) |
| Fechas-día | `YYYY-MM-DD` en **America/Bogota**; el cliente calcula el `date`, el server no hace math de timezone |
| IDs | UUID v4 generados por el **cliente** (permite offline + upsert idempotente) |
| Borrado | Soft delete (`deleted=1`); nada se borra físicamente |
| Sync | Toda tabla tiene `updated_at` (epoch ms, lo pone el server en cada write); pull incremental vía `GET /api/changes?since=` |
| Errores API | `{"error": {"code": "string", "message": "string"}}` con HTTP status apropiado |
| Idioma UI | Español; código/identificadores en inglés |

## Estructura del repo

```
cbum/
  PLAN.md, design-brief.md, DECISIONS.md
  specs/            ← estos archivos
  backend/          ← Agente A (wrangler, src/, migrations/, test/)
  ios/              ← Agente B (proyecto Xcode CBUM)
```

## Definition of Done global

**Backend:** `wrangler deploy` limpio; todos los endpoints responden según contracts (incluye colección de curls en `backend/test/smoke.sh`); tests unitarios de fórmulas pasan con los test vectors; MCP conectable desde Claude (custom connector) y los 13 tools funcionan end-to-end contra D1.

**iOS:** compila sin warnings en Xcode con Personal Team; corre en simulador; logging de un entreno completo funciona offline y sincroniza al reconectar; HealthKit escribe nutrición/workouts y lee peso/pasos/sueño; las 5 pantallas implementadas según specs.

**Integración (checklist final, cualquiera de los dos agentes la deja documentada):**
1. `POST /api/meals` desde curl → aparece en la app tras sync.
2. Entreno logueado en la app → visible vía tool MCP `get_workouts`.
3. Peso escrito en Apple Health (simulador) → llega a `body_metrics` → `get_energy_status` lo refleja.
4. `update_program` desde MCP → la app muestra el nuevo día de entreno en "Hoy".
