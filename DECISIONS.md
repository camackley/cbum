# DECISIONS — CBUM

Decisiones de implementación no cubiertas por las specs y desviaciones justificadas
del contrato. Archivo compartido por los dos agentes. Fuente de verdad de contratos:
`specs/01-contracts.md`.

- **Parte 1 · Backend (Agente A)** — Cloudflare Workers + D1 + REST + MCP (`backend/`).
- **Parte 2 · iOS (Agente B)** — app SwiftUI CBUM (`ios/`).

═══════════════════════════════════════════════════════════════════════════

# Parte 1 · Backend (Agente A)

## Estructura del repo

- **Todo el código del backend vive en `backend/`** (`backend/src`, `backend/migrations`, `backend/test`, `backend/wrangler.jsonc`, `backend/COACH.md`), como exigen `specs/00-overview.md` y B1. La raíz del repo es el proyecto `cbum/` y contiene `PLAN.md`, `design-brief.md`, `DECISIONS.md`, `specs/` y `backend/` (y `ios/` del Agente B). Ejecuta los comandos de wrangler/npm desde `backend/`.

## Correcciones post-review (2ª ronda, modelo Fable)

- **🔴 Catálogo invisible en el primer sync:** el seed usaba `updated_at=0` y `/api/changes` filtra `updated_at > since` con `since ≥ 0`, así que los 28 ejercicios nunca llegaban en el sync inicial de iOS. Ahora se siembran con `updated_at=1` → llegan con `since=0`. (`migrations/0002`).
- **🟠 `POST /api/body-metrics` reventaba con 500** si el mismo `id` llegaba con otra tupla `(type,ts,source)` (ej. editar la hora de un pesaje): el `ON CONFLICT(type,ts,source)` no cubre el PK `id`. Ahora es `DELETE por id` + `INSERT ON CONFLICT(tuple) DO UPDATE` en batch: idempotente, dedup de re-sync HealthKit (conserva el id existente en colisión de tupla) y sin 500 que envenene el outbox de iOS.
- **🟠 TDEE `calibrating` no inventa demografía:** si faltan `sex`/`age`/`height_cm`/`activity_factor` (o el peso), `tdee.kcal = null` en vez de calcular Mifflin con defaults. Además `PUT /api/goals`/`set_goals` ahora **validan** keys conocidas (contracts §1), tipos, y rango de `activity_factor` (1.2–1.9) → 422.
- **🟡 `sets` requerido en `POST /api/workouts`:** omitir la key `sets` daba `[]` por default y la reconciliación borraba TODOS los sets. Ahora es requerido (omisión → 422); un `[]` explícito sí limpia.
- **🟡 `POST /api/meals` exige `id` y `meal_group_id`** en el path REST (idempotencia + agrupación). El path MCP los genera antes de validar.
- **🟡 `get_body_metrics.ema_series`** se calcula sobre TODO el historial (carry-forward real) y se recorta al rango, en vez de re-sembrar el EMA con la lectura cruda del día `from`.
- **🟡 Cursor de `/api/changes` con margen de seguridad de 2s:** evita perder writes concurrentes que sellan `updated_at` justo antes del cursor. Re-entrega una ventana pequeña (idempotente en iOS). El smoke lo contempla.
- **🟡 MCP:** notificaciones (sin `id`) nunca reciben respuesta (202); `initialize` negocia `protocolVersion` a una versión soportada; secret comparado en tiempo constante.
- **Nits:** `deleteWorkout` no re-bumpea sets ya borrados; fallback de energía Atwater (2047/2048) en USDA; `pageSize` de USDA respeta `page_size`; `weightReadings` ordena por `date, ts`.

## Correcciones post-review (1ª ronda)

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
- **`adherence_pct`:** `complete_days_used / 21` (window_days), redondeado a **2 decimales** → reproduce el ejemplo de contracts §3.2 (16/21 = 0.76).
- **Redondeo:** pesos/EMA/tendencia a 1 decimal (82.4, 83.1); porcentajes, tasas y deltas a **2 decimales** (`weighed_pct`, `adherence_pct`, `rate_*`, `delta_7d_kg`, `delta_window_kg`) para reproducir los ejemplos del contrato (0.72, −0.21, −0.31, −0.62). `on_track` se evalúa sobre el valor **sin redondear** (el redondeo no debe voltear el veredicto que decide ajustar calorías).
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

═══════════════════════════════════════════════════════════════════════════

# Parte 2 · iOS (Agente B)

> **Propuestas de cambio de contrato:** ninguna. Para V2 se implementó EXACTO el
> delta `specs/v2/01-contracts-delta.md`. (El §R2 del delta ya se auto-corrige a
> `recovery_state:"caution"` para el vector-trampa; no requiere PROPUESTA.)

---

## 2026-07-15 · V2 — Sueño/recuperación + charts interactivos (I5 → I6)

### 🔴 Migración V1→V2: bundle id de producción (hallazgo crítico)
`ios/project.yml` estaba **desactualizado** respecto al `.pbxproj` que el usuario
tiene en producción: el YAML decía `com.mackley.cbum` + `DEVELOPMENT_TEAM:""`, pero
el proyecto commiteado en `main` usa **`com.camackley.cbum` + team `X6M3893ZHP`** (el
usuario lo cambió en Xcode y commiteó el pbxproj sin tocar el YAML). Regenerar con
`xcodegen generate` desde el YAML viejo **cambiaba el bundle id** → iOS trataría la V2
como app nueva y **perdería el store de SwiftData** (instrucción 7). Se corrigió
`project.yml` a los valores de producción (bundle id + team + versión 1.1/2). Ahora la
regeneración es fiel y la migración se preserva.
- **SwiftData**: la migración es un **no-op**. Los tipos nuevos de `body_metrics` son
  cases de enum (`BodyMetricType`) guardados como `typeRaw: String` — NO agregan
  propiedades stored a ningún `@Model` → el schema no cambia → el store V1 abre sin
  migración pesada y sin pérdida de datos.
- **Keychain**: el token sobrevive — `Keychain.service` es la constante
  `"com.mackley.cbum"`, independiente del bundle id.

### XcodeGen ahora sí disponible (deroga la nota de 2026-07-14)
El entorno tiene Xcode 26.6 + simuladores. Se instaló `xcodegen` (brew) y `project.yml`
volvió a ser la fuente reproducible real (glob de `CBUM/` → los archivos nuevos entran
sin editar el pbxproj). Build/test verificados en simulador iPhone 17.

### Recuperación — paridad EXACTA con el backend
- `FormulasKit` V2 replica `backend/src/lib/formulas.ts` §R5: `median`, `baseline28`
  (ventana [hoy−28, ayer], mín 14), `deviationPct`, `rhr/hrv/sleepStatus`,
  `midpointDrift`, `recoveryState` (reglas en orden). Tests `RecoveryFormulasTests`
  cubren TODOS los vectors del delta, incluido el **vector-trampa** (sleep 6.95 +
  rhr +5.2 + hrv −22.6 → `caution`, no `low`). 10 tests V2 verdes.
- `RecoveryCompute.build` es el MISMO algoritmo que `recovery.ts` (arma el shape §R2),
  compartido por el `MockAPIClient` y el **fallback local** del `TodayViewModel`
  (SwiftData) → la app offline y `get_recovery` del coach dan iguales números.

### HealthKit (I5 §1)
- Sueño con **fases**: ventana nocturna 18:00→18:00 (Bogotá) resuelta como
  `wakeDate = día(muestra.start + 6h)` (asigna [D−1 18:00, D 18:00) → fecha D). Antes
  V1 asignaba por `endDate` (follow-up que quedaba pendiente en DECISIONS V1): ahora es
  la ventana estricta del delta.
- `asleepUnspecified` suma a `core_hours` y a `sleep_hours` (delta §R1); `awake` NO
  suma a total. `midpoint_hour` = hora decimal local del punto medio del bloque
  principal (1er inicio → último fin de asleep*).
- **Dedup de fuentes**: si iPhone y wearable reportan la misma noche, se prefiere la
  fuente CON fases (deep/rem/core); empate → mayor tiempo asleep. Evita doble conteo.
- HRV/RHR/respiración: promedio discreto diario (1 valor/día). Composición
  (grasa%·100, masa magra kg): cada muestra, anchors por tipo como el peso.
- **Backfill 90d**: el primer import V2 trae 90 días (los baselines 28d necesitan
  historia); luego 14. Flag `hkBackfilledV2`. Toggles de importación por categoría en
  Ajustes (HealthKit no deja togglear permisos de LECTURA por API → esto controla qué
  importa la app), + `sleep_need_hours` editable.

### Charts V2 (I6 / delta §R6)
- `CBRangePicker` (1M/3M/6M/1A/TODO, default 3M) persistido por chart en UserDefaults;
  `TrendChart`, `SleepStackedBars`, `BaselineBandChart`, `CompositionChart` lo usan.
  La serie se filtra por rango; el EMA se calcula sobre la serie completa aguas arriba.
- **Bug 1** (peso multi-año ilegible): filtrado por rango + dominio Y de la serie
  **visible** ±5% + eje `d MMM` (≤6M) / `MMM yy` (mayores). Antes/después en el PR.
- **Bug 2** (RITMO partido): `StatCard` con `lineLimit(1)` + `minimumScaleFactor(0.6)`
  + `monospacedDigit` + sufijo con ancho reservado. **Caveat**: el "split en dos
  líneas" reportado depende del ancho del contenedor / Dynamic Type; con los valores
  del mock en el simulador iPhone 17 no se dispara (el mismo valor cabe en una línea).
  El fix es **defensivo**: garantiza UNA línea a cualquier ancho. El antes/después
  muestra además el cambio de formato (punto → coma es-CO) y la garantía de una línea.
- Scrubbing: `chartOverlay` + drag → línea vertical + lollipop (valor + fecha "14 jul"),
  haptic `.selection` al cambiar de punto, desvanece 2s tras soltar.
- Gaps de datos = huecos reales (puntos, sin línea interpolada) + banner cuando
  `data_gaps` no está vacío. PROHIBIDO interpolar (delta §R6 / principio de precisión).

### Formato es-CO
- `CBNumber` (Locale es_CO): `1.830`, `133,3`, `+0,07`. Se reemplazaron los
  `String(format:)`/`\(Int(...))` de UI en Features/ (Today, Progress, Nutrition,
  Session). **Excepciones no ruteadas** (no son cantidades decimales): el timer
  `MM:SS` (`%02d:%02d:%02d`) y la etiqueta ISO-week (`%04d-W%02d`).

### Mock determinista
Se eliminó `Double.random` del seed (aprendizaje del bug V1 de datos no
reproducibles): pesos con wobble determinista por índice. IDs deterministas
`mock-bm-<type>-<date>`. Seed V2: 60 días de recuperación con baselines estables
(rhr 58, hrv 62, midpoint 2.8) + HOY el vector-trampa, ~5 años de peso semanal (para
ejercitar 1A/TODO y demostrar el fix del Bug 1) y 13 semanas de composición.

### Hook de screenshots
`RootView` lee `CBUM_SCREEN` (env) para navegar a una pantalla en el arranque y los
rangos de chart se fijan por launch-args (`-cbum.chartRange.<id> <valor>` → UserDefaults)
para capturas deterministas. Sin efecto en producción (variable ausente).

---

## Checklist de integración (00-overview.md §DoD) — lado iOS

Estado y **cómo verificar** cada punto una vez el backend esté desplegado (en
Ajustes: apagar "Usar mock local", poner base URL + API token, "Probar conexión").

1. **`POST /api/meals` desde curl → aparece en la app tras sync.**
   Wiring iOS: `SyncEngine.pullChanges()` (trigger: foreground / pull-to-refresh /
   "Sincronizar ahora") llama `GET /api/changes?since=cursor` y hace upsert por id
   en SwiftData (`applyMeal`). NUTRICIÓN y HOY leen de SwiftData → el meal aparece.
   ✅ Implementado. Verificar: curl el POST, luego foreground la app.

2. **Entreno logueado en la app → visible vía tool MCP `get_workouts`.**
   Wiring iOS: al finalizar, `AppEnvironment.finishWorkout` encola
   `POST /api/workouts` (con sets) en el Outbox; el `SyncEngine` lo drena (idempotente
   por id). ✅ Implementado. Verificar: finalizar un entreno con red, luego
   `get_workouts` en Claude. El e1RM que muestra la app se calcula con `FormulasKit`
   (misma fórmula §5.3 que el server → deben coincidir; Aceptación I3 #3).

3. **Peso en Apple Health (simulador) → `body_metrics` → `get_energy_status`.**
   Wiring iOS: Ajustes → "Importar de Salud" (o foreground) corre
   `HealthKitService.readWeight()` (HKAnchoredObjectQuery) → `POST /api/body-metrics`
   por el Outbox (unique server dedup). HOY/PROGRESO reflejan la tendencia EMA.
   ✅ Implementado. Verificar: agregar peso en la app Salud del simulador, abrir CBUM.

4. **`update_program` desde MCP → la app muestra el nuevo día en "Hoy".**
   Wiring iOS: `pullChanges` aplica `program` (desactiva el anterior, `applyProgram`);
   HOY resuelve el día vía `/api/next-session` o el fallback local
   `FormulasKit.scheduledDayId` sobre el programa nuevo. ✅ Implementado.
   Verificar: `update_program` en Claude, luego foreground la app.

**Aceptaciones que requieren simulador (no ejecutables en este entorno; el código
que las soporta está completo):** modo avión (log meal/workout offline → outbox →
`GET /api/export` tras reconectar), kill a mitad de outbox sin duplicar (ids UUID +
upsert), meal en app Salud + borrado que desaparece de Salud, edición de porción
recalculada igual local y server, e1RM inválido no graficado.

---

## Checklist de integración V2 (`v2/00-overview-v2.md §DoD`) — lado iOS

Verificados en simulador contra el `MockAPIClient` (mismo shape/algoritmo que el
backend V2). Para verificar contra el backend real: Ajustes → apagar "Usar mock local",
poner base URL + API token.

1. **Sueño de anoche (con fases) visible en HOY y PROGRESO→RECUPERACIÓN tras sync.**
   ✅ Verificado en sim: HOY muestra la columna DORMIR (horas + mini-barra de fases) y
   el chip de `recovery_state`; RECUPERACIÓN muestra las barras apiladas por fase con
   línea de necesidad. Wiring: `TodayViewModel`/`ProgressViewModel` leen
   `GET /api/recovery` (+ `getBodyMetrics` por tipo) con fallback local `RecoveryCompute`.
   Verificar con backend: agregar una noche con fases en Salud (sim), "Importar de Salud".

2. **Charts con rango + scrub en Fuerza / Cuerpo / Recuperación.** ✅ Verificado:
   `CBRangePicker` (default 3M) persistido por chart; scrubbing con lollipop; cambio de
   rango filtra en memoria (< 100ms con ~1.800 puntos de EMA de 5 años).

3. **Los 2 bugs de UI cerrados con screenshot antes/después.** ✅ En `docs/screenshots/`
   (`03-cuerpo-ANTES` vs `05-cuerpo-todo-DESPUES` / `04-cuerpo-3m-DESPUES`).

4. **Integración: `get_recovery` desde el chat del coach responde lo MISMO que la app.**
   ⏳ Pendiente de backend V2 desplegado. Garantía de paridad: la app usa
   `RecoveryCompute.build` (mismo algoritmo que `backend/src/services/recovery.ts`) y
   `FormulasKit` V2 = `backend/src/lib/formulas.ts` §R5 (mismos test vectors verdes en
   ambos lados). Verificar: apagar mock, comparar `get_recovery` (Claude) vs
   HOY/RECUPERACIÓN para la misma fecha → mismos números.

5. **Backfill 90d → `body_metrics` con hrv/rhr/sueño históricos.** ✅ Código completo
   (`importFromHealthKit` con `vitalDays = hkBackfilledV2 ? 14 : 90`). Verificar con
   backend real + export tras el primer "Importar de Salud".

6. **`no_data` honesto (sin datos de sueño ≥3 días).** ✅ El chip muestra "SIN DATOS DE
   SUEÑO — revisa el puente" y RECUPERACIÓN muestra banner de `data_gaps`; el helper
   nunca interpola. (En el mock por defecto HOY tiene datos → `caution`; el escenario
   `no_data` se alcanza sin datos de sueño recientes.)

---

## 2026-07-14 · Correcciones post-review #2 (sub-agente Fable 5) + validación de compilación

El gate de licencia de Xcode se liberó a mitad de sesión, lo que permitió
**typecheck de casi toda la app** con `swiftc` contra el SDK de macOS: capa de datos
completa (Models + todos los Services + AppEnvironment) pasa **limpio**; el módulo
entero typechea salvo UN modificador iOS-only (`.textInputAutocapitalization(.never)`
en `SettingsView`), correcto en iOS y que solo falla al cross-compilar en macOS.
El full-typecheck descubrió y se corrigieron 3 errores propios preexistentes:
`CBFont.bodySM` no existía (16 usos → se añadió el helper), y dos closures de
datos de ejemplo (TrendChart/ComponentGallery `#Preview`) que hacían time-out de
inferencia de tipos (se anotaron los literales como `Double`).

Hallazgos del review corregidos:
- **🔴 Editar un set guardado no persistía.** `AppEnvironment.saveSet` solo insertaba;
  ahora hace update-in-place del `WorkoutSet` existente (antes el server recibía los
  valores viejos y la UI mostraba un valor fantasma).
- **🔴 "Descartar sesión" resucitaba el workout.** Con el POST-por-set, `discard` solo
  marcaba `deleted` local → el POST pendiente lo creaba en el server y el pull lo
  revivía. Nuevo `discardWorkout`: borra sets, quita del outbox el POST pendiente
  (`removePendingWorkout`) y encola `DELETE` si ya se había posteado. Además
  `lastSessionSets`/`maxHistoricalE1RM` excluyen workouts borrados.
- **🔴 Mock→live no reseteaba el cursor.** `switchClient` ahora pone `syncCursor=0` y
  purga los datos ya sincronizados (conserva el Outbox) → el primer pull contra el
  backend real baja todo el histórico sin mezclarse con la semilla del mock.
- **🟠 `per_100g` podía romper todo el pull.** Nuevo `JSONText<Macros>` decodifica
  objeto JSON, string JSON (columna TEXT de D1) o null tolerantemente.
- **🟠 Resume reconstruía desde el día del programa.** Ahora `resumeSession`
  reconstruye desde los `WorkoutSet` persistidos → funciona para entreno libre, día
  "rest", programa cambiado, y sin red.
- **🟠 Backoff 2s/8s/30s no existía.** `drainOutbox` ahora reintenta el item con
  backoff antes de dejarlo para el próximo trigger (FIFO, sin saltar items).
- **🟠 PATCH de macros omitía `portion_basis`/`fiber_g`** → el badge revertía a
  "weighed" tras el pull. Ahora se incluyen.
- **🟡 PRs del gráfico e1RM no filtraban por ejercicio** (marcaba PR de otro
  ejercicio en fecha coincidente). Corregido.
- **🟡 Re-import de HealthKit generaba UUIDs nuevos** → posible duplicado tras pull.
  `reconcileMetricId` reusa el id local por `(type,ts,source)`.
- **🟡 `applyMeal` no respetaba server-gana en `per_100g`** (conservaba local si el
  server mandaba null). Corregido.
- **🟡 Carrera del outbox:** `drainOutbox` re-fetchea el `OutboxItem` por id antes de
  borrarlo/mutarlo (un `enqueueWorkoutUpsert` durante un `await` podía eliminar el
  item en vuelo). 
- **Nits:** workouts vacíos de días pasados se borran (no quedan `finished=false`
  para siempre); el contador de "422" solo cuenta errores de validación (no 401);
  `syncNow` coalescing (un trigger durante un sync en curso corre otra pasada).

**Aceptados / follow-ups menores (documentados, no bloqueantes):**
- Sueño se asigna por el día del `endDate` (≈ fecha de despertar) en vez de la
  ventana estricta 18:00→18:00 de I2; difiere solo en siestas raras. Refinamiento
  pendiente (el cálculo local de la app es la fuente para ese `body_metric`).
- `markSyncError` marca el registro solo en POST de meals/workouts (no en
  PATCH/DELETE por-id); el 422 sigue visible como `lastError` del engine.
- Heurística "on-track" del peso en HOY usa el signo de `delta_7d` vs el signo de
  `goal_rate` (no la magnitud); PROGRESO/Cuerpo sí usa `energy-status.on_track`.

## 2026-07-14 · Correcciones post-review

**🔴 `applyProgram` activaba el programa viejo (FIX).** El feed `/api/changes`
trae dos filas de `program` al hacer `update_program` (vieja `active=0`, nueva
`active=1`); el código desactivaba todo y ponía `active=true` en cada fila
aplicada, así que según el orden podía quedar activo el viejo. Ahora se respeta
`d.active`/`d.deleted` y solo la fila con `active=1` desactiva a las demás
(invariante "un solo programa activo", independiente del orden de llegada).

**🟠 Pérdida de sets si la sesión no se finalizaba (FIX).** Antes el `POST
/api/workouts` solo se encolaba en `finishWorkout`. Ahora `AppEnvironment.saveSet`
encola el workout completo (upsert idempotente por id) tras **cada set**, con
`SyncEngine.enqueueWorkoutUpsert` que **reemplaza** el POST pendiente del mismo id
(evita pile-up). Además, al arrancar, `recoverUnfinishedWorkouts` finaliza y encola
las sesiones no finalizadas de días pasados (ya no quedan huérfanas aunque no
vuelvas el mismo día).

**🟠 §5.4 exige TODOS los sets prescritos — PARIDAD LOGRADA.** `suggestWeight` ahora
recibe `prescribedSets` y solo sube el peso si `working.count >= prescribed` **y**
todos cumplen `reps ≥ max` y `rir ≥ target` (antes 2/4 al tope ya subía — violaba
§5.4). Test nuevo `2of4 → repeat_weight`. **El backend (Agente A) aplicó la MISMA
regla** (`lastSessionSets.length ≥ prescription.sets`, ver sección Backend §5.4) →
iOS y server coinciden (Aceptación I3 #3). Los test vectors canónicos (4/4 → 82.5,
un set corto → 80) siguen pasando.

**Nit — 422 en workouts ahora tiene señal en UI.** Se añadió `Workout.syncError`;
`SyncEngine.markSyncError` lo marca y Ajustes cuenta meals + workouts con error.

**Nit — permiso de notificaciones se pide una sola vez** (flag en UserDefaults),
no en cada rest timer.

**Coordinación de `DECISIONS.md` (merge) — RESUELTO.** El backend (Agente A) ya
está en `main`. Esta rama se rebasó sobre `main` y `DECISIONS.md` quedó como un
archivo único: la sección **Backend (Agente A)** arriba y la sección **iOS
(Agente B)** abajo. Nombre `DECISIONS.md` como exigen `00-overview.md` y la
Aceptación I4 #5.

## 2026-07-14 · Entreno libre: prescripción por defecto
El "Entreno libre" (sin programa) usa una prescripción por defecto de
**3×[6–10] @ RIR 2, descanso 150s** por ejercicio agregado. Es un valor razonable
para hipertrofia; el usuario ajusta peso/reps/RIR por set igual. No viene de
contracts (el entreno libre no tiene `program_day`).

## 2026-07-14 · Entorno de build sin Xcode completo (verificación diferida)
**Contexto:** El entorno de desarrollo del agente solo tiene *Command Line Tools*,
no Xcode.app: no hay `xcodebuild`, SDK de iOS, simulador ni compilación de SwiftUI.
**Decisión:** Se produce todo el código Swift, el `.xcodeproj` y el `project.yml`
completos y revisados estructuralmente. La verificación final de "compila sin
warnings" y "corre en simulador" (Aceptación I1/global) queda a cargo del usuario
en su Mac con Xcode. El `.pbxproj` se validó estructuralmente (balance de llaves,
integridad de referencias de objetos) con un checker propio.
**Impacto:** Ninguno sobre el código entregable; solo sobre quién ejecuta la
verificación de compilación.

## 2026-07-14 · Generación del proyecto Xcode sin XcodeGen
**Contexto:** XcodeGen no está instalado y no se pueden añadir dependencias.
**Decisión:** `CBUM.xcodeproj/project.pbxproj` se generó con un generador propio
determinista (IDs de objeto secuenciales de 24 hex). Se versiona además
`ios/project.yml` como **fuente reproducible**: con XcodeGen instalado,
`xcodegen generate` reconstruye un proyecto equivalente.
**Impacto:** Al agregar archivos nuevos, regenerar (o añadirlos en Xcode). El
generador vive en el historial de la sesión; `project.yml` es la fuente canónica.

## 2026-07-14 · Tipografía: SF Pro condensada del sistema en vez de vendear Barlow
**Contexto:** El design system oficial define Display/Data en *Barlow Condensed*
(con *SF Pro Display* declarado como fallback para iOS) y Body en *Barlow*. La
regla del proyecto es **cero dependencias externas** y no incluir binarios extra.
**Decisión:** `CBFont` usa **SF Pro del sistema con `.fontWidth(.condensed)` y
peso `.black`** para display/números — el equivalente iOS-nativo que el propio
design declara como fallback — y SF Pro Text para cuerpo, SF Mono para mono. No se
vendean `.woff2`/`.ttf` de Barlow. La escala tipográfica (tamaños, tracking,
line-height) se mapea EXACTA a `tokens/typography.css`.
**Impacto:** Estética 1:1 en tamaños/tracking; la forma de las letras usa la
condensada de Apple en vez de Barlow. Si se quisiera fidelidad tipográfica total,
basta agregar los `.ttf` a `Resources/` y registrarlos en Info.plist
(`UIAppFonts`) y cambiar los builders de `CBFont` — sin tocar features.

## 2026-07-14 · Tokens: el design MCP reemplaza los defaults de I1
**Contexto:** I1 lista colores de fallback; instrucción 2 dice que el proyecto de
diseño oficial (MCP) es la fuente de verdad y reemplaza esos defaults.
**Decisión:** `Theme.swift` toma los valores oficiales de `tokens/colors.css`.
Diferencias notables respecto al fallback de I1:
- `textPrimary` = blanco cálido `#F2F1EA` (no beige); el beige queda como **acento**.
- `surfaceCard` = `#121211` (no `#111111`); se añaden surfaceRaised/Input/Pressed.
- `borderDefault` = `#33332E` (no `#2A2A2A`); se añaden subtle/strong.
- `success/PR` = lima ácida `#B6F03C` (no `#86EFAC`).
- `alert` = `#FF4A3D`; `estimated` = `#D6A63C`.
Los nombres de I1 (`CB.surface`, `CB.border`, `CB.success`, `CB.alert`,
`CB.estimated`, etc.) se conservan como **alias** a los semánticos oficiales para
no romper referencias.

## 2026-07-14 · SourceBadge con glifos SF Symbols (scale/tag/camera)
**Contexto:** I1 describe el badge con emojis ⚖️/🏷/📷; el design system oficial
usa su primitivo `Icon` con glifos `scale`/`tag`/`camera`.
**Decisión:** `SourceBadge` usa `CBIcon` (SF Symbols `scalemass`/`tag`/`camera`),
que es el enfoque oficial del design y da mejor VoiceOver y consistencia visual.
El texto ("PESADO/ETIQUETA/ESTIMADO") se mantiene. Semántica idéntica.

## 2026-07-14 · App icon diferido a I4
**Contexto:** I1 arma el asset catalog; I4 pide el icono definitivo (negro + "CBUM"
bone condensed). Generar PNG 1024 no es posible sin herramientas gráficas aquí.
**Decisión:** `Assets.xcassets/AppIcon.appiconset` queda estructurado (sin PNG) en
I1; el icono se genera/añade en I4 (pulido). No bloquea build de desarrollo.

## 2026-07-14 · I2 — verificación parcial posible sin Xcode
**FormulasKit** se compiló y ejecutó de forma nativa (swiftc, Foundation puro):
**24/24 tests PASAN**, incluidos los vectores canónicos EMA=80.14, e1RM=133.3,
sugerencia=82.5, TDEE=2720, Mifflin=2681.25. Además la capa de datos Foundation
(Enums, Macros, DTOs, DateUtils, APIClient, MockAPIClient, AppConfig) pasa
`swiftc -typecheck` limpio. Lo que toca SDK de iOS (SwiftData @Model, SyncEngine,
HealthKitService, AppEnvironment, componentes SwiftUI) se revisó manualmente; su
compilación se confirma en Xcode.

## 2026-07-14 · Mock API client como default de desarrollo
`AppConfig.useMockAPI` arranca en **true**: la app corre contra `MockAPIClient`
(datos semilla realistas + endpoints derivados calculados con FormulasKit) hasta
que el backend esté desplegado. Se cambia a `LiveAPIClient` desde Ajustes o
poniendo base URL + token. Intercambio en caliente vía `AppEnvironment.switchClient`.

## 2026-07-14 · Test target CBUMTests en el proyecto generado
Se añadió un target de unit-test (`CBUMTests`, con `FormulasKitTests.swift`) al
`.pbxproj` generado y a `project.yml`. El DoD de fórmulas queda cubierto; correr
los tests requiere Xcode (`Cmd+U`) ya que este entorno no tiene simulador.

## 2026-07-14 · PATCH de meal como diccionario libre
`APIClient.patchMeal(id:fields:)` toma `[String: Any]` (serializado con
JSONSerialization) porque el PATCH de contracts §3 acepta un subconjunto arbitrario
de campos. El outbox guarda ese dict tal cual y el SyncEngine lo reenvía.

## 2026-07-14 · Accesibilidad (I4 pulido)
- **VoiceOver:** los 12 componentes exponen `accessibilityLabel`/`Value` (anillos,
  stat cards, set logger, RIR, rest timer, badges, meal rows, volume bars, botones,
  tabs). Los gráficos (Swift Charts) tienen soporte VO limitado por el framework.
- **Dynamic Type:** los números/titulares display usan tamaños FIJOS a propósito
  (I1: "los números display pueden ser fijos" — la app se lee con el teléfono en el
  piso y la estética condensada depende del tamaño). El cuerpo usa `CBFont.body`
  (17/16). Escalado completo de Dynamic Type en cuerpo queda como follow-up menor;
  se centralizaría en `CBFont` (cambiar a `.system(.body)` relativo) sin tocar
  features. Se documenta honestamente en vez de sobre-afirmar.

## 2026-07-14 · App icon generado con CoreGraphics/CoreText
El icono (`AppIcon-1024.png`, negro puro + "CBUM" en condensada bone + barra beige)
se generó con un pequeño tool Swift (CoreText/ImageIO) porque no hay editor gráfico.
Vive en `Assets.xcassets/AppIcon.appiconset/`.

## 2026-07-14 · MacroRings: anillos concéntricos + kcal central (reconcilia I1 y design)
**Contexto:** I1 dice "anillo kcal exterior + 3 barras P/C/G"; el design describe
"tres anillos concéntricos P/C/G con kcal al centro".
**Decisión:** Se implementan **anillos concéntricos** (kcal exterior + proteína en
bone + carbos + grasa) con kcal consumidas/objetivo + restantes al centro, y una
**leyenda P/C/G** debajo (togglable). Excedido → color `alert`. Honra ambas fuentes.
