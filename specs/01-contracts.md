# 01 — Contratos compartidos (FUENTE DE VERDAD)

## 1. Schema D1 (SQLite)

Todas las tablas llevan `updated_at INTEGER NOT NULL` (epoch ms, seteado por el server en cada insert/update) y `deleted INTEGER NOT NULL DEFAULT 0`, salvo donde se indique.

```sql
CREATE TABLE meals (
  id TEXT PRIMARY KEY,                -- uuid v4 del cliente
  ts TEXT NOT NULL,                   -- ISO-8601 con offset
  date TEXT NOT NULL,                 -- YYYY-MM-DD (Bogotá), calculado por el cliente
  meal_group_id TEXT NOT NULL,        -- agrupa items de una misma comida
  name TEXT NOT NULL,
  quantity_g REAL,                    -- null si el registro es por totales de etiqueta
  kcal REAL NOT NULL, protein_g REAL NOT NULL,
  carbs_g REAL NOT NULL, fat_g REAL NOT NULL, fiber_g REAL,
  per_100g TEXT,                      -- JSON {kcal,protein_g,carbs_g,fat_g,fiber_g}; permite re-cálculo al editar porción
  source TEXT NOT NULL CHECK(source IN ('label','barcode','photo','manual')),
  confidence REAL NOT NULL,           -- 0..1
  portion_basis TEXT NOT NULL CHECK(portion_basis IN ('weighed','estimated')),
  fdc_id INTEGER, off_id TEXT,        -- referencia USDA / Open Food Facts
  notes TEXT, updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);
-- REGLA (precisión): si source='photo', fdc_id u off_id es OBLIGATORIO (validar en API y MCP).

CREATE TABLE exercises (
  id TEXT PRIMARY KEY,                -- slug estable, ej. 'barbell-bench-press'
  name TEXT NOT NULL,                 -- 'Press banca con barra'
  muscle_group TEXT NOT NULL CHECK(muscle_group IN ('chest','back','shoulders','biceps','triceps','quads','hamstrings','glutes','calves','abs')),
  pattern TEXT NOT NULL CHECK(pattern IN ('horizontal_push','vertical_push','horizontal_pull','vertical_pull','squat','hinge','lunge','isolation','carry','core')),
  equipment TEXT NOT NULL CHECK(equipment IN ('barbell','dumbbell','machine','cable','bodyweight','smith')),
  increment_kg REAL NOT NULL,         -- salto mínimo de carga (2.5 barra, 2.0 mancuerna, 5.0 pierna/máquina placa)
  updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE workouts (
  id TEXT PRIMARY KEY, ts_start TEXT NOT NULL, ts_end TEXT,
  date TEXT NOT NULL, program_day_id TEXT, notes TEXT,
  updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE sets (
  id TEXT PRIMARY KEY, workout_id TEXT NOT NULL REFERENCES workouts(id),
  exercise_id TEXT NOT NULL REFERENCES exercises(id),
  set_number INTEGER NOT NULL, weight_kg REAL NOT NULL,
  reps INTEGER NOT NULL, rir INTEGER NOT NULL CHECK(rir BETWEEN 0 AND 5),
  is_warmup INTEGER NOT NULL DEFAULT 0,
  e1rm_kg REAL,                       -- lo calcula el SERVER al insertar; null si fuera de rango de validez (§5.3)
  updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE body_metrics (
  id TEXT PRIMARY KEY, ts TEXT NOT NULL, date TEXT NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('weight_kg','steps','sleep_hours','resting_hr','active_kcal')),
  value REAL NOT NULL,
  source TEXT NOT NULL,               -- 'healthkit' | 'manual'
  updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
  UNIQUE(type, ts, source)            -- dedup de re-sync HealthKit
);
-- 'active_kcal' se almacena SOLO informativo. PROHIBIDO usarlo en TDEE o recomendaciones.

CREATE TABLE day_flags (
  date TEXT PRIMARY KEY,
  logging_complete INTEGER NOT NULL DEFAULT 0,  -- el usuario/coach confirma que ese día se logueó TODO lo comido
  updated_at INTEGER NOT NULL
);

CREATE TABLE program (
  id TEXT PRIMARY KEY, active INTEGER NOT NULL DEFAULT 1,
  start_date TEXT NOT NULL,           -- ancla el schedule (§4)
  json TEXT NOT NULL,                 -- schema §4, validar al escribir
  updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE goals (                  -- key-value
  key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL
);
-- keys requeridas: target_kcal, target_protein_g, target_carbs_g, target_fat_g,
-- goal_weight_kg, goal_rate_kg_per_week (negativo = perder), sex ('m'|'f'),
-- age, height_cm, activity_factor (1.2–1.9, solo para fallback Mifflin)
```

**weight_trend y tdee NO se materializan**: se calculan on-read (§5). La data es pequeña; cero riesgo de cache desactualizado.

## 2. Autenticación

- REST: header `Authorization: Bearer ${API_TOKEN}` en todo `/api/*`. `API_TOKEN` es un secret de Wrangler. 401 si falta/incorrecto.
- MCP: montado en `POST /mcp/${MCP_SECRET}` (secret largo en la URL; los custom connectors de Claude no mandan headers custom). 404 si el secret no coincide.

## 3. REST API

Base: `https://<worker>.workers.dev`. Todos los bodies son JSON. Los POST son **upserts por id** (idempotentes, re-intentables desde el outbox de iOS).

| Método y ruta | Request | Response 200 |
|---|---|---|
| `GET /api/health` | — | `{"ok":true,"version":"1"}` |
| `POST /api/meals` | `{"meals":[Meal,...]}` (campos de la tabla, sin updated_at/deleted) | `{"upserted":n}` |
| `GET /api/meals?from=YYYY-MM-DD&to=YYYY-MM-DD` | — | `{"meals":[Meal,...]}` (deleted=0) |
| `PATCH /api/meals/:id` | `{"quantity_g":250}` u otros campos. Si viene `quantity_g` y hay `per_100g` → server recalcula macros = per_100g × quantity_g/100 | Meal actualizado |
| `DELETE /api/meals/:id` | — | `{"ok":true}` (soft) |
| `POST /api/workouts` | `{"workout":{...,"sets":[Set,...]}}` — server calcula `e1rm_kg` por set (§5.3). El set de sets del payload es **autoritativo**: sets del workout ausentes del payload se soft-borran (reconciliación de ediciones). | Workout con sets y e1rm calculados |
| `GET /api/workouts?from&to&exercise_id` | — | `{"workouts":[{...,"sets":[...]},...]}` |
| `DELETE /api/workouts/:id` | — | soft delete workout + sets |
| `GET /api/exercises` | — | `{"exercises":[...]}` |
| `POST /api/exercises` | `{"exercises":[Exercise,...]}` | `{"upserted":n}` |
| `POST /api/body-metrics` | `{"metrics":[...]}` — upsert por (type,ts,source) | `{"upserted":n}` |
| `GET /api/body-metrics?type&from&to` | — | `{"metrics":[...]}` |
| `PUT /api/days/:date` | `{"logging_complete":true}` | `{"ok":true}` |
| `GET /api/goals` / `PUT /api/goals` | PUT: `{"goals":{"target_kcal":"2600",...}}` (merge) | `{"goals":{...}}` |
| `GET /api/program` | — | `{"program":{id,start_date,json:{...}}}` o `{"program":null}` |
| `PUT /api/program` | `{"start_date":"2026-07-20","json":{...}}` — validar §4; desactiva el anterior | program guardado |
| `GET /api/summary/today?date=` | — | §3.1 |
| `GET /api/energy-status` | — | §3.2 |
| `GET /api/progress?exercise_id=` | — | §3.3 |
| `GET /api/next-session?date=` | — | §3.4 |
| `GET /api/changes?since=<epoch_ms>` | — | `{"cursor":<now_ms>,"meals":[...],"workouts":[...],"sets":[...],"body_metrics":[...],"exercises":[...],"program":[...],"goals":[...],"day_flags":[...]}` — incluye deleted=1 para que iOS borre local |
| `GET /api/export` | — | dump JSON completo de todas las tablas |

### 3.1 `GET /api/summary/today`
```json
{ "date":"2026-07-14",
  "intake":{"kcal":1830,"protein_g":142,"carbs_g":160,"fat_g":58,"fiber_g":21},
  "targets":{"kcal":2600,"protein_g":180,"carbs_g":260,"fat_g":80},
  "precision":{"weighed_pct":0.72,"items":9,"low_confidence_items":1},
  "weight":{"trend_kg":82.4,"delta_7d_kg":-0.31,"last_reading_kg":82.1,"last_reading_date":"2026-07-14"},
  "tdee":{"kcal":2720,"status":"adaptive"},
  "session":{"program_day_id":"upper_a","name":"Upper A","exercise_count":6,"completed_today":false},
  "logging_complete":false }
```

### 3.2 `GET /api/energy-status`
```json
{ "tdee":{"kcal":2720,"status":"adaptive","window_days":21,"complete_days_used":16,"weighins_used":19},
  "weight":{"trend_kg":82.4,"trend_series":[{"date":"2026-06-24","ema_kg":83.1},...],
            "delta_window_kg":-0.62},
  "intake":{"avg_kcal_complete_days":2480,"adherence_pct":0.76},
  "goal":{"rate_target_kg_per_week":-0.35,"rate_actual_kg_per_week":-0.21,"on_track":false},
  "recommendation_basis":"adaptive" }
```
`status`: `"adaptive"` si en la ventana de 21 días hay ≥10 días `logging_complete` **y** ≥10 pesajes; si no, `"calibrating"` y `tdee.kcal` = Mifflin-St Jeor (§5.2 fallback).

### 3.3 `GET /api/progress?exercise_id=`
Sin `exercise_id`: `{"weekly_volume":[{"week":"2026-W28","muscle_group":"chest","effective_sets":12},...], "prs_recent":[{exercise_id,name,e1rm_kg,date},...]}`.
Con `exercise_id`: además `{"e1rm_series":[{date,e1rm_kg}],"best_sets":[{weight_kg,reps,rir,date}]}` (e1rm_series = mejor e1rm válido por sesión).

### 3.4 `GET /api/next-session?date=`
Resuelve qué día del schedule toca (§4) y calcula sugerencias (§5.4):
```json
{ "program_day_id":"upper_a","name":"Upper A",
  "exercises":[{"exercise_id":"barbell-bench-press","name":"Press banca con barra",
    "sets":4,"rep_range":[6,8],"target_rir":2,"rest_sec":180,
    "suggested_weight_kg":82.5,"suggestion_reason":"double_progression_increase",
    "last_session":{"date":"2026-07-10","top_set":{"weight_kg":80,"reps":8,"rir":2}}},...] }
```
`suggestion_reason` ∈ `double_progression_increase | repeat_weight | no_history` (si `no_history`, `suggested_weight_kg:null`).

## 4. Schema del programa (`program.json`)

```json
{ "version":1, "name":"Upper/Lower 4d",
  "days":[
    {"id":"upper_a","name":"Upper A","exercises":[
      {"exercise_id":"barbell-bench-press","sets":4,"rep_range":[6,8],
       "target_rir":2,"rest_sec":180,"notes":"pausa en pecho"} ]} ],
  "schedule":["upper_a","lower_a","rest","upper_b","lower_b","rest","rest"] }
```
Reglas: `schedule` = ciclo repetido de longitud arbitraria de day-ids o `"rest"`, anclado a `start_date`: el día que toca en fecha F = `schedule[(diasEntre(start_date, F)) % schedule.length]`. Todo `exercise_id` debe existir en `exercises`. `rep_range` = [min,max] con min ≤ max. Validación estricta al `PUT /api/program` y en tool `update_program`; error 422 con detalle.

## 5. Fórmulas (exactas — con test vectors)

### 5.1 Tendencia de peso (EMA)
Sobre pesajes diarios ordenados por fecha (si hay varios en un día, promediarlos): `ema_0 = w_0`; `ema_i = ema_{i-1} + 0.1 × (w_i − ema_{i-1})`. Días sin pesaje: el EMA no cambia (carry forward).
**Test:** pesos [80.0, 81.0, —, 80.5] → EMA [80.0, 80.1, 80.1, 80.14].

### 5.2 TDEE adaptativo
Ventana: últimos 21 días. Requiere ≥10 días `logging_complete` y ≥10 pesajes; si no → `calibrating` con fallback **Mifflin-St Jeor**: hombres `10×peso + 6.25×altura_cm − 5×edad + 5`, mujeres `… − 161`, × `activity_factor` (usa `weight.trend_kg` actual como peso).
Adaptativo: `avg_intake` = promedio de kcal SOLO de días complete dentro de la ventana. `ΔEMA` = ema(último día) − ema(primer día de la ventana). `daily_balance = ΔEMA × 7700 / 21`. **`TDEE = avg_intake − daily_balance`**.
**Test:** avg_intake=2500, ΔEMA=−0.6 kg en 21 días → daily_balance = −220 → TDEE = **2720**.

### 5.3 e1RM (Epley ajustado por RIR)
`e1rm = weight_kg × (1 + (reps + rir) / 30)`. **Válido solo si** `is_warmup=0` y `(reps + rir) ≤ 12`; fuera de eso `e1rm_kg = null` (no se grafica ni cuenta para PR). Redondear a 1 decimal.
**Tests:** 100kg × 8 reps @ RIR 2 → 100×(1+10/30) = **133.3**. 60kg × 12 @ RIR 3 → null (15 > 12).

### 5.4 Sugerencia de peso (doble progresión)
Para cada ejercicio del día: tomar la última sesión (no deleted) que lo incluyó, sets de trabajo (is_warmup=0). Si **todos** los sets prescritos cumplieron `reps ≥ rep_range.max` con `rir ≥ target_rir` → sugerir `último_peso + increment_kg` (`double_progression_increase`). Si no → `último_peso` (`repeat_weight`). Sin historial → null (`no_history`). Si la sesión anterior usó pesos distintos por set, "último_peso" = peso del último set de trabajo.
**Test:** prescrito 4×[6,8] RIR 2, increment 2.5; última sesión 4 sets de 80kg×8@2 → sugerir **82.5**. Si un set fue 80×7@2 → sugerir **80**.

### 5.5 Sets efectivos y PR
Set efectivo: `is_warmup=0 AND rir ≤ 4`. Volumen semanal = count de sets efectivos por `muscle_group` por semana ISO. **PR**: set con `e1rm_kg` válido > máximo e1rm válido histórico previo de ese ejercicio.

## 6. Tools MCP

Servidor: nombre `cbum-coach`, versión `1.0.0`. Cada tool retorna texto (JSON serializado legible). Errores como `isError:true` con mensaje accionable.

| Tool | Input (JSON Schema resumido) | Comportamiento |
|---|---|---|
| `resolve_food` | `{query?: string, barcode?: string, page_size?: number=5}` | barcode → Open Food Facts; query → USDA FDC (prioriza Foundation/SR Legacy sobre Branded). Retorna candidatos con macros **per 100g** + fdc_id/off_id. Nunca inventa: si no hay match, lo dice y sugiere pedir etiqueta |
| `log_meal` | `{ts, date, meal_group_id?, items:[{name, quantity_g?, per_100g?, kcal, protein_g, carbs_g, fat_g, fiber_g?, source, confidence, portion_basis, fdc_id?, off_id?, notes?}]}` | Valida regla: source='photo' ⇒ fdc_id/off_id presente. Genera ids/meal_group_id si faltan. Upsert en `meals`. Retorna resumen + totales del día vs targets |
| `get_meals` | `{from, to}` | Meals agrupados por día con totales y % weighed |
| `get_workouts` | `{from, to, exercise_id?}` | Workouts con sets, e1rm, PRs marcados |
| `get_body_metrics` | `{type, from, to}` | Serie cruda + (para weight_kg) serie EMA |
| `get_progress` | `{exercise_id?}` | = §3.3 |
| `get_energy_status` | `{}` | = §3.2 |
| `get_program` | `{}` | Programa activo + qué día toca hoy |
| `update_program` | `{start_date, json}` | Valida §4 (verifica exercise_ids contra catálogo); reemplaza activo |
| `get_goals` / `set_goals` | set: `{goals:{key:value}}` (merge) | keys de §1 goals |
| `mark_day` | `{date, logging_complete: boolean}` | Marca día completo para TDEE |
| `log_workout` | mismo shape que `POST /api/workouts` | Fallback si el usuario dicta un entreno por chat |

## 7. HealthKit ↔ backend (mapeo)

| Dirección | Dato | HK identifier | Backend |
|---|---|---|---|
| App → HK | comida | `dietaryEnergyConsumed`, `dietaryProtein`, `dietaryCarbohydrates`, `dietaryFatTotal`, `dietaryFiber` | desde `meals` |
| App → HK | entreno | `HKWorkout` activityType `.traditionalStrengthTraining` (ts_start/ts_end) | desde `workouts` |
| HK → App → API | peso | `bodyMass` (kg) | `body_metrics type=weight_kg` |
| HK → App → API | pasos | `stepCount` (total diario) | `type=steps` |
| HK → App → API | sueño | `sleepAnalysis` (horas asleep/noche) | `type=sleep_hours` |
| HK → App → API | kcal activas | `activeEnergyBurned` (total diario) | `type=active_kcal` (solo informativo) |
