# B2 — REST API (Agente A)

**Prerrequisito:** B1 completo. La API es EXACTAMENTE la de `01-contracts.md` §3 — este spec solo agrega detalles de implementación.

## Arquitectura interna
Separar **servicios** de **rutas**: `src/services/{meals,workouts,metrics,program,goals,analytics}.ts` contienen la lógica; las rutas Hono y (en B4) los tools MCP llaman a los MISMOS servicios. Nada de lógica duplicada entre REST y MCP.

## Detalles por grupo

**Upserts idempotentes.** `POST /api/meals|/api/workouts|/api/body-metrics|/api/exercises` hacen `INSERT ... ON CONFLICT(id) DO UPDATE` (body_metrics: conflicto por `(type,ts,source)`). Reintentos del outbox de iOS no deben duplicar ni fallar. `updated_at = now()` en cada write, SIEMPRE server-side.

**Workouts.** El POST recibe workout + sets anidados; transacción (D1 `batch`): upsert workout, upsert sets calculando `e1rm_kg` con la fórmula de contracts §5.3 (helper `computeE1rm(weight,reps,rir,isWarmup): number|null` en `src/lib/formulas.ts`). DELETE marca deleted=1 en workout y sus sets.

**PATCH /api/meals/:id.** Si trae `quantity_g` y la fila tiene `per_100g`: recalcular kcal/protein/carbs/fat/fiber = per_100g × quantity_g/100 (redondeo 1 decimal). Si no hay `per_100g`, aceptar solo edición directa de macros y forzar `portion_basis='estimated'` a menos que el request diga lo contrario.

**Validación (zod) estricta:** rechazar 422 con mensaje claro cuando: meal con `source='photo'` sin `fdc_id` ni `off_id`; `confidence` fuera de [0,1]; `rir` fuera de 0–5; `rep_range` inválido en program; `exercise_id` inexistente en program o sets; fechas mal formadas.

**`GET /api/changes?since=`.** Query por tabla `WHERE updated_at > ?` (incluye deleted=1). Respuesta con `cursor` = `now()` del server al inicio del request. `since=0` = sync inicial completo. Incluir workouts y sus sets aunque solo el set haya cambiado.

**Endpoints de análisis** (`summary/today`, `energy-status`, `progress`, `next-session`): delegan a `src/services/analytics.ts` que se implementa en **B3**. En B2 dejar el servicio con stubs tipados y los endpoints cableados.

**Export.** `GET /api/export`: JSON con todas las tablas completas (incl. deleted) + `exported_at`.

## Aceptación
- `backend/test/smoke.sh`: secuencia curl que crea 1 meal, 1 workout con 3 sets, 2 body metrics, marca un día completo, edita porción de meal (verifica recálculo), lista changes con `since` y verifica cursor incremental. Debe correr limpio contra el worker desplegado.
- POST repetido con el mismo body → mismos counts, sin duplicados.
- Los 422 de validación devuelven `{"error":{code,message}}`.
