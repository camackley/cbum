# DECISIONS — Backend (Agente A)

Registro de decisiones de implementación no cubiertas por las specs y desviaciones justificadas del contrato. El agente de iOS depende de este archivo y de `specs/01-contracts.md`.

## Estructura del repo

- **Todo el código del backend vive en `backend/`** (`backend/src`, `backend/migrations`, `backend/test`, `backend/wrangler.jsonc`, `backend/COACH.md`), como exigen `specs/00-overview.md` y B1. La raíz del repo es el proyecto `cbum/` y contiene `PLAN.md`, `design-brief.md`, `DECISIONS.md`, `specs/` y `backend/` (y `ios/` del Agente B). Ejecuta los comandos de wrangler/npm desde `backend/`.

## Correcciones post-review

- **TDEE en onboarding (bloqueante corregido):** el balance energético solo se computa si el trend de peso (EMA) **cubre toda la ventana de 21 días** (hay EMA en `windowStart`). Si el primer pesaje es posterior a `windowStart` (primeras ~3 semanas), `adaptiveTdee` recibe `trendCoversWindow=false` y cae a `calibrating`/Mifflin. Esto evita el bug de `emaFirst=0` que producía ΔEMA≈peso y un TDEE absurdo presentado como fiable. Coherente con "primeras 2 semanas = provisional" del PLAN.
- **Días `logging_complete` sin comida:** un día marcado complete con 0 meals o `kcal < 500` se **excluye** del promedio de ingesta del TDEE (arrastraría el TDEE hacia abajo). Se reporta en `energy-status.tdee.incomplete_days_excluded`. `complete_days_used` refleja los días realmente usados (post-exclusión) y alimenta el gate de ≥10 días.
- **Sugerencia de peso (§5.4):** además de que todos los sets cumplan reps/RIR, se exige que la última sesión haya hecho **al menos tantos sets de trabajo como los prescritos** (`lastSessionSets.length ≥ prescription.sets`); si hizo menos, se repite peso (no se sube).
- **Reconciliación de sets en `POST /api/workouts`:** el array `sets` del payload es autoritativo; los sets del workout ausentes se **soft-borran** (`deleted=1`) para reflejar ediciones que quitan un set. Cambio anotado en `specs/01-contracts.md §3`. iOS re-postea el workout completo; no hay `DELETE /api/sets/:id`.
- **`energy-status.as_of_date`:** fecha ancla de la ventana (último pesaje). Evita presentar data vieja como actual si el usuario deja de pesarse. Campo nuevo (aditivo, no rompe iOS).
- **Auth bearer:** comparación en tiempo constante (evita timing side-channel).
- **Endpoint `GET /api/debug/resolve` eliminado** (era solo verificación de B3). `resolve_food` se ejerce vía el tool MCP.

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

## Fechas

- El server no hace math de timezone (overview). `src/lib/dates.ts` solo hace aritmética de calendario sobre `YYYY-MM-DD` anclada a medianoche UTC (estable, sin DST). El `date` siempre lo calcula el cliente en America/Bogota.

## Health

- Además del `GET /api/health` con auth (contracts §3), se expone `GET /health` público (sin token) para monitoreo/uptime. No sustituye al de contrato.

---

## Secrets a configurar (antes de `wrangler deploy`)

```sh
cd backend   # todos los comandos de wrangler se ejecutan desde backend/

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
