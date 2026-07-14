-- CBUM — schema inicial. Fuente de verdad: specs/01-contracts.md §1.
-- Todas las tablas: updated_at INTEGER (epoch ms, server) + deleted (soft delete), salvo goals/day_flags/food_cache.

CREATE TABLE meals (
  id TEXT PRIMARY KEY,                -- uuid v4 del cliente
  ts TEXT NOT NULL,                   -- ISO-8601 con offset
  date TEXT NOT NULL,                 -- YYYY-MM-DD (Bogotá), calculado por el cliente
  meal_group_id TEXT NOT NULL,        -- agrupa items de una misma comida
  name TEXT NOT NULL,
  quantity_g REAL,                    -- null si el registro es por totales de etiqueta
  kcal REAL NOT NULL, protein_g REAL NOT NULL,
  carbs_g REAL NOT NULL, fat_g REAL NOT NULL, fiber_g REAL,
  per_100g TEXT,                      -- JSON {kcal,protein_g,carbs_g,fat_g,fiber_g}
  source TEXT NOT NULL CHECK(source IN ('label','barcode','photo','manual')),
  confidence REAL NOT NULL,           -- 0..1
  portion_basis TEXT NOT NULL CHECK(portion_basis IN ('weighed','estimated')),
  fdc_id INTEGER, off_id TEXT,        -- referencia USDA / Open Food Facts
  notes TEXT, updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE exercises (
  id TEXT PRIMARY KEY,                -- slug estable, ej. 'barbell-bench-press'
  name TEXT NOT NULL,
  muscle_group TEXT NOT NULL CHECK(muscle_group IN ('chest','back','shoulders','biceps','triceps','quads','hamstrings','glutes','calves','abs')),
  pattern TEXT NOT NULL CHECK(pattern IN ('horizontal_push','vertical_push','horizontal_pull','vertical_pull','squat','hinge','lunge','isolation','carry','core')),
  equipment TEXT NOT NULL CHECK(equipment IN ('barbell','dumbbell','machine','cable','bodyweight','smith')),
  increment_kg REAL NOT NULL,
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
  e1rm_kg REAL,                       -- lo calcula el SERVER al insertar; null si fuera de rango (§5.3)
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

CREATE TABLE day_flags (
  date TEXT PRIMARY KEY,
  logging_complete INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
);

CREATE TABLE program (
  id TEXT PRIMARY KEY, active INTEGER NOT NULL DEFAULT 1,
  start_date TEXT NOT NULL,
  json TEXT NOT NULL,
  updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE goals (
  key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL
);

-- Índices (B1): pull incremental /api/changes usa updated_at; queries por fecha/ejercicio.
CREATE INDEX idx_meals_date ON meals(date);
CREATE INDEX idx_meals_updated ON meals(updated_at);
CREATE INDEX idx_sets_exercise ON sets(exercise_id);
CREATE INDEX idx_sets_workout ON sets(workout_id);
CREATE INDEX idx_sets_updated ON sets(updated_at);
CREATE INDEX idx_workouts_date ON workouts(date);
CREATE INDEX idx_workouts_updated ON workouts(updated_at);
CREATE INDEX idx_body_metrics_type_date ON body_metrics(type, date);
CREATE INDEX idx_body_metrics_updated ON body_metrics(updated_at);
CREATE INDEX idx_exercises_updated ON exercises(updated_at);
CREATE INDEX idx_program_updated ON program(updated_at);
CREATE INDEX idx_goals_updated ON goals(updated_at);
CREATE INDEX idx_day_flags_updated ON day_flags(updated_at);
