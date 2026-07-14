# DECISIONS — Backend (Agente A)

Registro de decisiones de implementación no cubiertas por las specs y desviaciones justificadas del contrato. El agente de iOS depende de este archivo y de `specs/01-contracts.md`.

## Stack y arquitectura

- **Router:** Hono sobre Cloudflare Workers, TypeScript estricto.
- **Persistencia:** D1 con helpers finos sobre `env.DB.prepare()` (sin ORM). Motivo: el modelo de datos es pequeño y los upserts son directos; un ORM no aporta.
- **MCP:** handler JSON-RPC 2.0 **stateless** sobre `POST /mcp/:secret` (Streamable HTTP mínimo: `initialize`, `tools/list`, `tools/call`). Se eligió sobre `McpAgent`/Durable Objects porque no requiere estado entre requests ni DO, y es suficiente para los custom connectors de Claude (contracts §2, B4 permite esta alternativa).
- **Validación:** zod compartido entre REST y MCP (mismas reglas 422). La lógica vive en `src/services/*` y tanto rutas Hono como tools MCP la invocan (sin duplicar).

## Schema

- `@cloudflare/workers-types` fijado a `^5` (lo exige `wrangler@4.110`).
- Tabla extra `food_cache` (migración `0003`), requerida por B3; no está en contracts §1 porque es cache interno del server, invisible para iOS. No afecta el contrato.
- Índices `updated_at` por tabla para el pull incremental de `/api/changes`.
- Ejercicios sembrados: 28 (contracts/B1). `updated_at=0` en el seed; los writes del server lo sobrescriben.

## Análisis (B3) — decisiones no cubiertas por contracts

- **Ancla de la ventana de 21 días en `/api/energy-status`:** el endpoint no recibe `date`. Se ancla al **último día con pesaje** (último punto de la serie EMA). `summary/today` sí usa el `date` recibido. Motivo: el server no hace math de timezone; el dato manda.
- **`weighins_used`:** se cuentan **días distintos con pesaje** dentro de la ventana (no lecturas crudas), coherente con "pesaje diario".
- **`adherence_pct`:** `complete_days_used / 21` (window_days). Reproduce el ejemplo de contracts §3.2 (16/21 ≈ 0.76).
- **`rate_actual_kg_per_week`:** `ΔEMA_ventana / (21/7)` = ΔEMA/3.
- **`goal.on_track`:** `true` si `|rate_actual − rate_target| ≤ 0.1` kg/sem. Reproduce el ejemplo (−0.21 vs −0.35 → false).
- **TDEE `calibrating` sin peso ni `goal_weight_kg`:** `tdee.kcal = null` (no hay Mifflin fiable sin peso). Con peso/goal disponible se usa Mifflin normal.
- **`next-session` "última sesión":** workout más reciente con `date < date_objetivo` que incluya el ejercicio con set de trabajo. `top_set` = set de trabajo más pesado de esa sesión.
- **`progress.prs_recent`:** PRs detectados recorriendo cada ejercicio en orden cronológico (e1rm válido > máximo previo); se devuelven los 10 más recientes.
- **Cache de alimentos:** TTL 30 días (contracts/B3); key de query = `q:{djb2(query)}:{page_size}`. Ranking USDA por `dataType` (Foundation < SR Legacy < Branded) preservando el orden de relevancia dentro de cada tipo.
- **Endpoint `GET /api/debug/resolve`:** util de verificación de `resolve_food` (bajo auth). No forma parte del contrato iOS; se puede quitar.

## Fechas

- El server no hace math de timezone (overview). `src/lib/dates.ts` solo hace aritmética de calendario sobre `YYYY-MM-DD` anclada a medianoche UTC (estable, sin DST). El `date` siempre lo calcula el cliente en America/Bogota.

## Health

- Además del `GET /api/health` con auth (contracts §3), se expone `GET /health` público (sin token) para monitoreo/uptime. No sustituye al de contrato.

---

## Secrets a configurar (antes de `wrangler deploy`)

```sh
# 1. Crear la base D1 y copiar el database_id impreso a wrangler.jsonc
wrangler d1 create cbum-db

# 2. Aplicar migraciones (local ya hecho; remoto para producción)
wrangler d1 migrations apply cbum-db --remote

# 3. Secrets (contracts §2 + B3)
wrangler secret put API_TOKEN     # bearer para /api/* (token largo aleatorio)
wrangler secret put MCP_SECRET    # segmento de URL para /mcp/:secret (largo, aleatorio)
wrangler secret put FDC_API_KEY   # USDA FoodData Central: https://fdc.nal.usda.gov/api-key-signup.html

# 4. Deploy
wrangler deploy
```

Para desarrollo local, los secrets viven en `backend/.dev.vars` (git-ignored).

## Conectar el MCP en Claude (custom connector)

Tras el deploy, agrega un **custom connector** en Claude (Settings → Connectors) con la URL:

```
https://<worker>.workers.dev/mcp/<MCP_SECRET>
```

- Transporte: Streamable HTTP (JSON-RPC 2.0 stateless). Métodos: `initialize`, `tools/list`, `tools/call`, `ping`.
- El secret va en la URL (los custom connectors de Claude no envían headers custom); secret incorrecto → 404.
- `tools/list` debe mostrar los **13 tools**. Pega `backend/COACH.md` en las instrucciones del Claude Project.
- Requiere plan Pro/Max de Claude para custom connectors.

## Verificación local (hecha)

- `npm test` → 19 tests verdes (todos los vectors de contracts §5).
- `test/smoke.sh` → 21/21 checks contra el worker local.
- MCP: initialize + tools/list (13) + E2E `resolve_food`→`log_meal` (fila con fdc_id) + `update_program` inválido (error claro, DB intacta) + secret incorrecto 404.
- `resolve_food`: USDA "chicken breast raw" (SR Legacy primero) y barcode OFF (Nutella) OK.

## Comando para arrancar dev local

```sh
cd backend
npm install
wrangler d1 migrations apply cbum-db --local
wrangler dev --local
# smoke: BASE_URL=http://localhost:8788 API_TOKEN=dev-local-token ./test/smoke.sh
```
