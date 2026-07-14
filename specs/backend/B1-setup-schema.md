# B1 — Setup, schema y seed (Agente A)

**Prerrequisito:** leer `specs/00-overview.md` y `specs/01-contracts.md`.

## Objetivo
Proyecto Cloudflare Workers desplegable con D1 migrado, catálogo de ejercicios sembrado, auth funcionando y `GET /api/health` respondiendo.

## Stack
- TypeScript estricto, **Hono** como router, Wrangler (última versión estable).
- D1 binding `DB`. Secrets: `API_TOKEN`, `MCP_SECRET`, `FDC_API_KEY`.
- Sin ORM pesado: helpers finos sobre `env.DB.prepare()` (o drizzle si acelera — decisión del agente, documentar en DECISIONS.md).

## Pasos
1. `backend/`: `wrangler.jsonc` con binding D1 (`cbum-db`), `compatibility_date` reciente, `nodejs_compat` habilitado.
2. `migrations/0001_init.sql`: schema EXACTO de contracts §1 + índices:
   `meals(date)`, `sets(exercise_id)`, `sets(workout_id)`, `workouts(date)`, `body_metrics(type,date)`, y `updated_at` en cada tabla para `/api/changes`.
3. `migrations/0002_seed_exercises.sql`: catálogo inicial (~28 ejercicios). Incluir mínimo, con `id` slug, muscle_group/pattern/equipment/increment_kg correctos:
   - Pecho: barbell-bench-press (2.5), incline-db-press (2.0), machine-chest-press (5.0), cable-fly (2.5)
   - Espalda: pull-up (2.5), lat-pulldown (5.0), barbell-row (2.5), seated-cable-row (5.0), machine-row (5.0)
   - Hombro: overhead-press (2.5), db-shoulder-press (2.0), db-lateral-raise (1.0), cable-lateral-raise (1.0), reverse-pec-deck (5.0)
   - Bíceps: db-curl (1.0), ez-bar-curl (2.5), cable-curl (2.5)
   - Tríceps: cable-pushdown (2.5), overhead-cable-extension (2.5), skull-crusher (2.5)
   - Pierna: barbell-back-squat (2.5), hack-squat (5.0), leg-press (5.0), romanian-deadlift (2.5), leg-extension (5.0), seated-leg-curl (5.0), hip-thrust (5.0), standing-calf-raise (5.0)
4. Middleware de auth (contracts §2) aplicado a `/api/*`. Ruta MCP se reserva para B4.
5. Utilidades compartidas en `src/lib/`: `now()` (epoch ms), respuesta de error estándar, validación con zod de todos los inputs.
6. `src/index.ts` monta Hono; `GET /api/health` → `{"ok":true,"version":"1"}`.

## Aceptación
- `wrangler d1 migrations apply` local y remoto sin errores.
- `curl` sin token → 401; con token → health 200.
- `SELECT count(*) FROM exercises` ≥ 28.
