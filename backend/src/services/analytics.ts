import type { Env } from '../types';
import {
  emaSeries,
  adaptiveTdee,
  suggestWeight,
  weeklyEffectiveSets,
  round1,
  round2,
  type WeightReading,
  type EmaPoint,
  type MifflinInput,
} from '../lib/formulas';
import { addDays, daysBetween } from '../lib/dates';
import { getGoals } from './goals';
import { getActiveProgram } from './program';

const WINDOW_DAYS = 21;
const LOW_CONFIDENCE = 0.7;

// ── Shapes EXACTAS de contracts §3.1–3.4 ─────────────────────────────────────
export interface SummaryToday {
  date: string;
  intake: { kcal: number; protein_g: number; carbs_g: number; fat_g: number; fiber_g: number };
  targets: { kcal: number | null; protein_g: number | null; carbs_g: number | null; fat_g: number | null };
  precision: { weighed_pct: number; items: number; low_confidence_items: number };
  weight: { trend_kg: number | null; delta_7d_kg: number | null; last_reading_kg: number | null; last_reading_date: string | null };
  tdee: { kcal: number | null; status: string };
  session: { program_day_id: string | null; name: string | null; exercise_count: number; completed_today: boolean };
  logging_complete: boolean;
}
export interface EnergyStatus {
  as_of_date: string | null; // ancla de la ventana (último pesaje); evita presentar data vieja como actual
  tdee: { kcal: number | null; status: string; window_days: number; complete_days_used: number; weighins_used: number; incomplete_days_excluded: number };
  weight: { trend_kg: number | null; trend_series: { date: string; ema_kg: number }[]; delta_window_kg: number | null };
  intake: { avg_kcal_complete_days: number | null; adherence_pct: number | null };
  goal: { rate_target_kg_per_week: number | null; rate_actual_kg_per_week: number | null; on_track: boolean };
  recommendation_basis: string;
}
export interface ProgressResult {
  weekly_volume: { week: string; muscle_group: string; effective_sets: number }[];
  prs_recent: { exercise_id: string; name: string; e1rm_kg: number; date: string }[];
  e1rm_series?: { date: string; e1rm_kg: number }[];
  best_sets?: { weight_kg: number; reps: number; rir: number; date: string }[];
}
export interface NextSession {
  program_day_id: string;
  name?: string;
  exercises?: {
    exercise_id: string;
    name: string;
    sets: number;
    rep_range: [number, number];
    target_rir: number;
    rest_sec: number;
    suggested_weight_kg: number | null;
    suggestion_reason: string;
    last_session: { date: string; top_set: { weight_kg: number; reps: number; rir: number } } | null;
  }[];
}

// ── Helpers de datos ─────────────────────────────────────────────────────────
async function weightReadings(env: Env, upTo?: string): Promise<WeightReading[]> {
  const clause = upTo ? 'AND date <= ?' : '';
  const binds = upTo ? [upTo] : [];
  const { results } = await env.DB.prepare(
    `SELECT date, value FROM body_metrics WHERE type='weight_kg' AND deleted=0 ${clause} ORDER BY date ASC, ts ASC`,
  )
    .bind(...binds)
    .all<{ date: string; value: number }>();
  return results.map((r) => ({ date: r.date, kg: r.value }));
}

// kcal totales por fecha en un rango (solo meals no borrados).
async function mealKcalByDate(env: Env, from: string, to: string): Promise<Map<string, number>> {
  const { results } = await env.DB.prepare(
    `SELECT date, SUM(kcal) AS kcal FROM meals WHERE deleted=0 AND date >= ? AND date <= ? GROUP BY date`,
  )
    .bind(from, to)
    .all<{ date: string; kcal: number }>();
  return new Map(results.map((r) => [r.date, r.kcal]));
}

async function completeDaysInRange(env: Env, from: string, to: string): Promise<string[]> {
  const { results } = await env.DB.prepare(
    `SELECT date FROM day_flags WHERE logging_complete=1 AND date >= ? AND date <= ?`,
  )
    .bind(from, to)
    .all<{ date: string }>();
  return results.map((r) => r.date);
}

// Cuenta días distintos con pesaje en un rango.
async function weighinDaysInRange(env: Env, from: string, to: string): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT COUNT(DISTINCT date) AS n FROM body_metrics WHERE type='weight_kg' AND deleted=0 AND date >= ? AND date <= ?`,
  )
    .bind(from, to)
    .first<{ n: number }>();
  return row?.n ?? 0;
}

function num(v: string | undefined): number | null {
  if (v == null) return null;
  const n = parseFloat(v);
  return Number.isFinite(n) ? n : null;
}

// ema en una fecha concreta = último punto de la serie con date <= fecha (carry-forward).
function emaAt(series: EmaPoint[], date: string): number | null {
  let val: number | null = null;
  for (const p of series) {
    if (p.date <= date) val = p.ema;
    else break;
  }
  return val;
}

// ── Núcleo energético (reusado por summary/today y energy-status) ────────────
interface EnergyCore {
  refDate: string | null;
  series: EmaPoint[];
  windowSeries: EmaPoint[];
  trendKg: number | null;
  emaFirst: number | null;
  emaLast: number | null;
  deltaWindow: number | null;
  completeDayKcals: number[];
  completeDaysUsed: number;
  incompleteDaysExcluded: number; // días marcados complete pero con 0 meals o kcal < MIN
  weighinsUsed: number;
  avgKcal: number | null;
  tdeeKcal: number | null;
  status: 'adaptive' | 'calibrating';
}

const MIN_COMPLETE_KCAL = 500; // un día "complete" por debajo de esto es sospechoso → se excluye del TDEE

async function energyCore(env: Env, refDateParam?: string): Promise<EnergyCore> {
  const goals = await getGoals(env);
  const readings = await weightReadings(env);
  const series = emaSeries(readings);

  // Ancla de la ventana: el date param, o el último día con pesaje.
  const refDate = refDateParam ?? (series.length ? series[series.length - 1]!.date : null);

  if (!refDate) {
    return {
      refDate: null, series, windowSeries: [], trendKg: null, emaFirst: null, emaLast: null,
      deltaWindow: null, completeDayKcals: [], completeDaysUsed: 0, incompleteDaysExcluded: 0,
      weighinsUsed: 0, avgKcal: null, tdeeKcal: null, status: 'calibrating',
    };
  }

  const windowStart = addDays(refDate, -(WINDOW_DAYS - 1));
  const windowSeries = series.filter((p) => p.date >= windowStart && p.date <= refDate);
  const trendKg = emaAt(series, refDate);
  // emaFirst = EMA en windowStart (carry-forward). null si el trend NO cubre la ventana
  // (primer pesaje posterior a windowStart) → NO es un ΔEMA fiable → calibrating.
  const emaFirst = emaAt(series, windowStart);
  const emaLast = trendKg;
  const trendCoversWindow = emaFirst != null;
  const deltaWindow = emaFirst != null && emaLast != null ? round2(emaLast - emaFirst) : null;

  // Días complete en ventana → kcal por día. Excluir días marcados complete pero
  // con 0 meals o kcal < MIN (mal marcados): arrastrarían el promedio del TDEE hacia abajo.
  const completeDates = await completeDaysInRange(env, windowStart, refDate);
  const kcalByDate = await mealKcalByDate(env, windowStart, refDate);
  const completeDayKcals: number[] = [];
  let incompleteDaysExcluded = 0;
  for (const d of completeDates) {
    const k = kcalByDate.get(d);
    if (k == null || k < MIN_COMPLETE_KCAL) incompleteDaysExcluded++;
    else completeDayKcals.push(k);
  }
  const weighinsUsed = await weighinDaysInRange(env, windowStart, refDate);
  const avgKcal = completeDayKcals.length ? round1(completeDayKcals.reduce((a, b) => a + b, 0) / completeDayKcals.length) : null;

  // Mifflin fallback: SOLO con datos reales de goals + peso tendencia. Nunca inventar
  // demografía (PRINCIPIO PRECISIÓN: rechazar/anular, no rellenar con defaults).
  const sexRaw = goals.sex;
  const ageN = num(goals.age);
  const heightN = num(goals.height_cm);
  const afN = num(goals.activity_factor);
  const weightN = trendKg ?? num(goals.goal_weight_kg);
  const hasMifflinInputs =
    (sexRaw === 'm' || sexRaw === 'f') && ageN != null && heightN != null && afN != null && weightN != null && weightN > 0;

  const mifflin: MifflinInput = {
    sex: sexRaw === 'f' ? 'f' : 'm',
    age: ageN ?? 30,
    heightCm: heightN ?? 175,
    activityFactor: afN ?? 1.5,
    weightKg: weightN ?? 0,
  };

  const tdee = adaptiveTdee({
    windowDays: WINDOW_DAYS,
    completeDayKcals,
    weighinsCount: weighinsUsed,
    emaFirst: emaFirst ?? 0, // solo se usa si trendCoversWindow (garantiza no-null)
    emaLast: emaLast ?? 0,
    trendCoversWindow,
    mifflin,
  });

  // adaptive: el kcal viene del balance (no necesita Mifflin) → siempre válido.
  // calibrating: kcal = Mifflin → válido SOLO si tenemos todos los inputs reales; si no, null.
  const tdeeKcal = tdee.status === 'adaptive' ? tdee.kcal : hasMifflinInputs ? tdee.kcal : null;

  return {
    refDate, series, windowSeries, trendKg, emaFirst, emaLast, deltaWindow,
    completeDayKcals, completeDaysUsed: completeDayKcals.length, incompleteDaysExcluded,
    weighinsUsed, avgKcal, tdeeKcal, status: tdee.status,
  };
}

// ── §3.2 energy-status ───────────────────────────────────────────────────────
export async function energyStatus(env: Env): Promise<EnergyStatus> {
  const goals = await getGoals(env);
  const core = await energyCore(env);

  const rateTarget = num(goals.goal_rate_kg_per_week);
  // rate_actual = ΔEMA por semana = ΔEMA / (window_days/7). on_track se evalúa SIN redondear
  // (evita que ±0.05 de redondeo voltee el veredicto que decide ajustar calorías).
  const rawRate = core.emaFirst != null && core.emaLast != null ? (core.emaLast - core.emaFirst) / (WINDOW_DAYS / 7) : null;
  const rateActual = rawRate != null ? round2(rawRate) : null;
  const onTrack = rateTarget != null && rawRate != null ? Math.abs(rawRate - rateTarget) <= 0.1 : false;

  // adherence = días complete / ventana (2 decimales, como el ejemplo 16/21 ≈ 0.76).
  const adherence = round2(core.completeDaysUsed / WINDOW_DAYS);

  return {
    as_of_date: core.refDate,
    tdee: {
      kcal: core.tdeeKcal,
      status: core.status,
      window_days: WINDOW_DAYS,
      complete_days_used: core.completeDaysUsed,
      weighins_used: core.weighinsUsed,
      incomplete_days_excluded: core.incompleteDaysExcluded,
    },
    weight: {
      trend_kg: core.trendKg != null ? round1(core.trendKg) : null,
      trend_series: core.windowSeries.map((p) => ({ date: p.date, ema_kg: round1(p.ema) })),
      delta_window_kg: core.deltaWindow,
    },
    intake: {
      avg_kcal_complete_days: core.avgKcal,
      adherence_pct: core.completeDaysUsed ? adherence : (core.refDate ? adherence : null),
    },
    goal: {
      rate_target_kg_per_week: rateTarget,
      rate_actual_kg_per_week: rateActual,
      on_track: onTrack,
    },
    recommendation_basis: core.status,
  };
}

// ── §3.1 summary/today ───────────────────────────────────────────────────────
export async function summaryToday(env: Env, date: string): Promise<SummaryToday> {
  const goals = await getGoals(env);

  // Intake + precisión del día.
  const { results: dayMeals } = await env.DB.prepare(
    `SELECT kcal, protein_g, carbs_g, fat_g, fiber_g, portion_basis, confidence FROM meals WHERE deleted=0 AND date=?`,
  )
    .bind(date)
    .all<{ kcal: number; protein_g: number; carbs_g: number; fat_g: number; fiber_g: number | null; portion_basis: string; confidence: number }>();

  const intake = dayMeals.reduce(
    (a, m) => ({
      kcal: a.kcal + m.kcal,
      protein_g: a.protein_g + m.protein_g,
      carbs_g: a.carbs_g + m.carbs_g,
      fat_g: a.fat_g + m.fat_g,
      fiber_g: a.fiber_g + (m.fiber_g ?? 0),
    }),
    { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 },
  );
  const items = dayMeals.length;
  const weighed = dayMeals.filter((m) => m.portion_basis === 'weighed').length;
  const lowConf = dayMeals.filter((m) => m.confidence < LOW_CONFIDENCE).length;

  // Peso: EMA hasta la fecha.
  const readings = await weightReadings(env, date);
  const series = emaSeries(readings);
  const trendKg = emaAt(series, date);
  const ema7ago = emaAt(series, addDays(date, -7));
  const delta7 = trendKg != null && ema7ago != null ? round2(trendKg - ema7ago) : null;
  const lastReading = readings.length ? readings[readings.length - 1]! : null;

  // TDEE anclado a la fecha.
  const core = await energyCore(env, date);

  // Sesión del día (schedule §4).
  const session = await sessionForDate(env, date);
  const completedToday = await workoutExistsForDate(env, date);

  // logging_complete flag.
  const flag = await env.DB.prepare(`SELECT logging_complete FROM day_flags WHERE date=?`).bind(date).first<{ logging_complete: number }>();

  return {
    date,
    intake: {
      kcal: round1(intake.kcal),
      protein_g: round1(intake.protein_g),
      carbs_g: round1(intake.carbs_g),
      fat_g: round1(intake.fat_g),
      fiber_g: round1(intake.fiber_g),
    },
    targets: {
      kcal: num(goals.target_kcal),
      protein_g: num(goals.target_protein_g),
      carbs_g: num(goals.target_carbs_g),
      fat_g: num(goals.target_fat_g),
    },
    precision: {
      weighed_pct: items ? round2(weighed / items) : 0,
      items,
      low_confidence_items: lowConf,
    },
    weight: {
      trend_kg: trendKg != null ? round1(trendKg) : null,
      delta_7d_kg: delta7,
      last_reading_kg: lastReading?.kg ?? null,
      last_reading_date: lastReading?.date ?? null,
    },
    tdee: { kcal: core.tdeeKcal, status: core.status },
    session: {
      program_day_id: session?.dayId ?? null,
      name: session?.name ?? null,
      exercise_count: session?.exerciseCount ?? 0,
      completed_today: completedToday,
    },
    logging_complete: !!(flag && flag.logging_complete),
  };
}

// ── Resolución del schedule (§4) ─────────────────────────────────────────────
interface SessionInfo {
  dayId: string;
  name: string | null;
  exerciseCount: number;
}
async function sessionForDate(env: Env, date: string): Promise<SessionInfo | null> {
  const program = await getActiveProgram(env);
  if (!program || !program.json?.schedule?.length) return null;
  const diff = daysBetween(program.start_date, date);
  const len = program.json.schedule.length;
  const idx = ((diff % len) + len) % len;
  const dayId = program.json.schedule[idx]!;
  if (dayId === 'rest') return { dayId: 'rest', name: 'Descanso', exerciseCount: 0 };
  const day = program.json.days.find((d) => d.id === dayId);
  if (!day) return { dayId, name: null, exerciseCount: 0 };
  return { dayId, name: day.name, exerciseCount: day.exercises.length };
}

async function workoutExistsForDate(env: Env, date: string): Promise<boolean> {
  const row = await env.DB.prepare(`SELECT 1 AS x FROM workouts WHERE deleted=0 AND date=? LIMIT 1`).bind(date).first<{ x: number }>();
  return !!row;
}

// ── §3.3 progress ────────────────────────────────────────────────────────────
interface SetJoin {
  exercise_id: string;
  name: string;
  muscle_group: string;
  date: string;
  weight_kg: number;
  reps: number;
  rir: number;
  is_warmup: number;
  e1rm_kg: number | null;
}
async function allSetsJoined(env: Env, exerciseId?: string): Promise<SetJoin[]> {
  const clause = exerciseId ? 'AND s.exercise_id=?' : '';
  const binds = exerciseId ? [exerciseId] : [];
  const { results } = await env.DB.prepare(
    `SELECT s.exercise_id, e.name, e.muscle_group, w.date, s.weight_kg, s.reps, s.rir, s.is_warmup, s.e1rm_kg
     FROM sets s
     JOIN workouts w ON w.id=s.workout_id AND w.deleted=0
     JOIN exercises e ON e.id=s.exercise_id
     WHERE s.deleted=0 ${clause}
     ORDER BY w.date ASC, s.set_number ASC`,
  )
    .bind(...binds)
    .all<SetJoin>();
  return results;
}

export async function progress(env: Env, exerciseId?: string): Promise<ProgressResult> {
  const sets = await allSetsJoined(env);

  const weekly_volume = weeklyEffectiveSets(
    sets.map((s) => ({ date: s.date, muscle_group: s.muscle_group, is_warmup: !!s.is_warmup, rir: s.rir })),
  );

  // PRs: por ejercicio, en orden cronológico, e1rm válido > máximo previo.
  const byExercise = new Map<string, SetJoin[]>();
  for (const s of sets) {
    if (s.e1rm_kg == null) continue;
    const arr = byExercise.get(s.exercise_id) ?? [];
    arr.push(s);
    byExercise.set(s.exercise_id, arr);
  }
  const prs: { exercise_id: string; name: string; e1rm_kg: number; date: string }[] = [];
  for (const [exId, arr] of byExercise) {
    let max = -Infinity;
    for (const s of arr) {
      if (s.e1rm_kg! > max) {
        max = s.e1rm_kg!;
        prs.push({ exercise_id: exId, name: s.name, e1rm_kg: s.e1rm_kg!, date: s.date });
      }
    }
  }
  prs.sort((a, b) => b.date.localeCompare(a.date));
  const prs_recent = prs.slice(0, 10);

  const base: ProgressResult = { weekly_volume, prs_recent };
  if (!exerciseId) return base;

  // Detalle por ejercicio.
  const exSets = await allSetsJoined(env, exerciseId);
  // e1rm_series = mejor e1rm válido por sesión (date).
  const bestByDate = new Map<string, number>();
  const bestSetByDate = new Map<string, { weight_kg: number; reps: number; rir: number; date: string }>();
  for (const s of exSets) {
    if (s.e1rm_kg != null) {
      const prev = bestByDate.get(s.date);
      if (prev == null || s.e1rm_kg > prev) {
        bestByDate.set(s.date, s.e1rm_kg);
        bestSetByDate.set(s.date, { weight_kg: s.weight_kg, reps: s.reps, rir: s.rir, date: s.date });
      }
    }
  }
  const e1rm_series = [...bestByDate.entries()]
    .map(([date, e1rm_kg]) => ({ date, e1rm_kg }))
    .sort((a, b) => a.date.localeCompare(b.date));
  const best_sets = [...bestSetByDate.values()].sort((a, b) => a.date.localeCompare(b.date));

  return { ...base, e1rm_series, best_sets };
}

// ── §3.4 next-session ────────────────────────────────────────────────────────
export async function nextSession(env: Env, date: string): Promise<NextSession> {
  const program = await getActiveProgram(env);
  if (!program || !program.json?.schedule?.length) {
    return { program_day_id: 'rest' };
  }
  const diff = daysBetween(program.start_date, date);
  const len = program.json.schedule.length;
  const idx = ((diff % len) + len) % len;
  const dayId = program.json.schedule[idx]!;
  if (dayId === 'rest') return { program_day_id: 'rest' };

  const day = program.json.days.find((d) => d.id === dayId);
  if (!day) return { program_day_id: dayId };

  // Catálogo para nombres + increment.
  const { results: catalog } = await env.DB.prepare(
    `SELECT id, name, increment_kg FROM exercises WHERE deleted=0`,
  ).all<{ id: string; name: string; increment_kg: number }>();
  const catMap = new Map(catalog.map((e) => [e.id, e]));

  const exercises: NonNullable<NextSession['exercises']> = [];
  for (const pex of day.exercises) {
    const cat = catMap.get(pex.exercise_id);
    const lastSets = await lastWorkingSets(env, pex.exercise_id, date);
    const increment = cat?.increment_kg ?? 2.5;
    const suggestion = suggestWeight(
      { repRange: pex.rep_range, targetRir: pex.target_rir, sets: pex.sets },
      lastSets.map((s) => ({ set_number: s.set_number, weight_kg: s.weight_kg, reps: s.reps, rir: s.rir })),
      increment,
    );
    // top_set = set de trabajo más pesado de la última sesión.
    const topSet = lastSets.length
      ? lastSets.reduce((a, b) => (b.weight_kg > a.weight_kg ? b : a))
      : null;
    const lastSession = topSet
      ? { date: topSet.date, top_set: { weight_kg: topSet.weight_kg, reps: topSet.reps, rir: topSet.rir } }
      : null;

    exercises.push({
      exercise_id: pex.exercise_id,
      name: cat?.name ?? pex.exercise_id,
      sets: pex.sets,
      rep_range: pex.rep_range,
      target_rir: pex.target_rir,
      rest_sec: pex.rest_sec,
      suggested_weight_kg: suggestion.suggested_weight_kg,
      suggestion_reason: suggestion.suggestion_reason,
      last_session: lastSession,
    });
  }

  return { program_day_id: dayId, name: day.name, exercises };
}

interface WorkingSetRow {
  set_number: number;
  weight_kg: number;
  reps: number;
  rir: number;
  date: string;
}
// Sets de trabajo (is_warmup=0) de la última sesión (workout más reciente, date < ref) que incluyó el ejercicio.
async function lastWorkingSets(env: Env, exerciseId: string, beforeDate: string): Promise<WorkingSetRow[]> {
  const lastW = await env.DB.prepare(
    `SELECT w.id, w.date FROM workouts w
     JOIN sets s ON s.workout_id=w.id AND s.deleted=0 AND s.exercise_id=? AND s.is_warmup=0
     WHERE w.deleted=0 AND w.date < ?
     ORDER BY w.ts_start DESC LIMIT 1`,
  )
    .bind(exerciseId, beforeDate)
    .first<{ id: string; date: string }>();
  if (!lastW) return [];
  const { results } = await env.DB.prepare(
    `SELECT set_number, weight_kg, reps, rir FROM sets WHERE workout_id=? AND exercise_id=? AND is_warmup=0 AND deleted=0 ORDER BY set_number ASC`,
  )
    .bind(lastW.id, exerciseId)
    .all<{ set_number: number; weight_kg: number; reps: number; rir: number }>();
  return results.map((r) => ({ ...r, date: lastW.date }));
}
