// Fórmulas exactas de contracts §5. Funciones PURAS y testeables sin D1.
// Los test vectors de §5 son obligatorios (test/formulas.test.ts).

import { enumerateDays, isoWeek } from './dates';

export function round1(x: number): number {
  return Math.round(x * 10) / 10;
}

// ── §5.1 Tendencia de peso (EMA) ────────────────────────────────────────────
export interface WeightReading {
  date: string; // YYYY-MM-DD
  kg: number;
}
export interface EmaPoint {
  date: string;
  ema: number;
}

// ema_0 = w_0 ; ema_i = ema_{i-1} + 0.1×(w_i − ema_{i-1}).
// Varios pesajes el mismo día → se promedian. Días sin pesaje → carry-forward.
export function emaSeries(readings: WeightReading[]): EmaPoint[] {
  if (readings.length === 0) return [];

  // Promediar por día.
  const byDay = new Map<string, { sum: number; n: number }>();
  for (const r of readings) {
    const acc = byDay.get(r.date) ?? { sum: 0, n: 0 };
    acc.sum += r.kg;
    acc.n += 1;
    byDay.set(r.date, acc);
  }
  const dailyAvg = new Map<string, number>();
  for (const [date, { sum, n }] of byDay) dailyAvg.set(date, sum / n);

  const days = [...dailyAvg.keys()].sort();
  const first = days[0]!;
  const last = days[days.length - 1]!;

  const out: EmaPoint[] = [];
  let ema: number | null = null;
  for (const day of enumerateDays(first, last)) {
    const w = dailyAvg.get(day);
    if (w !== undefined) {
      ema = ema === null ? w : ema + 0.1 * (w - ema);
    }
    // Si no hay pesaje, ema no cambia (carry-forward). ema nunca es null aquí
    // porque el primer día del rango siempre tiene lectura.
    out.push({ date: day, ema: ema as number });
  }
  return out;
}

// ── §5.2 TDEE ────────────────────────────────────────────────────────────────
export interface MifflinInput {
  sex: 'm' | 'f';
  age: number;
  heightCm: number;
  activityFactor: number;
  weightKg: number; // usar weight.trend_kg actual
}

// Mifflin-St Jeor × activity_factor. Fallback cuando no hay data suficiente.
export function mifflinTdee(i: MifflinInput): number {
  const base = 10 * i.weightKg + 6.25 * i.heightCm - 5 * i.age + (i.sex === 'm' ? 5 : -161);
  return round1(base * i.activityFactor);
}

export interface AdaptiveTdeeInput {
  windowDays: number; // 21
  completeDayKcals: number[]; // kcal de días logging_complete dentro de la ventana
  weighinsCount: number; // pesajes dentro de la ventana
  emaFirst: number; // ema del primer día de la ventana
  emaLast: number; // ema del último día de la ventana
  mifflin: MifflinInput; // para el fallback calibrating
}
export interface AdaptiveTdeeResult {
  kcal: number;
  status: 'adaptive' | 'calibrating';
  window_days: number;
  complete_days_used: number;
  weighins_used: number;
}

// adaptive si ≥10 días complete Y ≥10 pesajes en la ventana; si no, calibrating (Mifflin).
export function adaptiveTdee(i: AdaptiveTdeeInput): AdaptiveTdeeResult {
  const completeDays = i.completeDayKcals.length;
  const isAdaptive = completeDays >= 10 && i.weighinsCount >= 10;

  let kcal: number;
  if (isAdaptive) {
    const avgIntake = i.completeDayKcals.reduce((a, b) => a + b, 0) / completeDays;
    const deltaEma = i.emaLast - i.emaFirst;
    const dailyBalance = (deltaEma * 7700) / i.windowDays;
    kcal = round1(avgIntake - dailyBalance);
  } else {
    kcal = mifflinTdee(i.mifflin);
  }

  return {
    kcal,
    status: isAdaptive ? 'adaptive' : 'calibrating',
    window_days: i.windowDays,
    complete_days_used: completeDays,
    weighins_used: i.weighinsCount,
  };
}

// ── §5.3 e1RM (Epley ajustado por RIR) ───────────────────────────────────────
// Válido solo si is_warmup=0 y (reps+rir) ≤ 12; fuera de eso null.
export function computeE1rm(
  weightKg: number,
  reps: number,
  rir: number,
  isWarmup: boolean,
): number | null {
  if (isWarmup) return null;
  if (reps + rir > 12) return null;
  return round1(weightKg * (1 + (reps + rir) / 30));
}

// ── §5.4 Sugerencia de peso (doble progresión) ───────────────────────────────
export interface Prescription {
  repRange: [number, number]; // [min,max]
  targetRir: number;
}
export interface WorkingSet {
  set_number: number;
  weight_kg: number;
  reps: number;
  rir: number;
}
export type SuggestionReason =
  | 'double_progression_increase'
  | 'repeat_weight'
  | 'no_history';
export interface WeightSuggestion {
  suggested_weight_kg: number | null;
  suggestion_reason: SuggestionReason;
}

// lastSessionSets = sets de trabajo (is_warmup=0) de la última sesión que incluyó el ejercicio.
export function suggestWeight(
  prescription: Prescription,
  lastSessionSets: WorkingSet[],
  incrementKg: number,
): WeightSuggestion {
  if (lastSessionSets.length === 0) {
    return { suggested_weight_kg: null, suggestion_reason: 'no_history' };
  }
  const [, max] = prescription.repRange;
  // "último_peso" = peso del último set de trabajo (mayor set_number).
  const lastSet = lastSessionSets.reduce((a, b) => (b.set_number >= a.set_number ? b : a));
  const lastWeight = lastSet.weight_kg;

  const allHit = lastSessionSets.every((s) => s.reps >= max && s.rir >= prescription.targetRir);
  if (allHit) {
    return {
      suggested_weight_kg: round1(lastWeight + incrementKg),
      suggestion_reason: 'double_progression_increase',
    };
  }
  return { suggested_weight_kg: lastWeight, suggestion_reason: 'repeat_weight' };
}

// ── §5.5 Sets efectivos y PR ─────────────────────────────────────────────────
export interface SetForVolume {
  date: string;
  muscle_group: string;
  is_warmup: boolean;
  rir: number;
}
export interface WeeklyVolumeRow {
  week: string;
  muscle_group: string;
  effective_sets: number;
}

// Set efectivo: is_warmup=0 AND rir ≤ 4. Agrupado por semana ISO y muscle_group.
export function weeklyEffectiveSets(sets: SetForVolume[]): WeeklyVolumeRow[] {
  const counts = new Map<string, number>();
  for (const s of sets) {
    if (s.is_warmup || s.rir > 4) continue;
    const week = isoWeek(s.date);
    const key = `${week}|${s.muscle_group}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  const rows: WeeklyVolumeRow[] = [];
  for (const [key, effective_sets] of counts) {
    const [week, muscle_group] = key.split('|');
    rows.push({ week: week!, muscle_group: muscle_group!, effective_sets });
  }
  // Orden estable: semana asc, luego muscle_group.
  rows.sort((a, b) => (a.week === b.week ? a.muscle_group.localeCompare(b.muscle_group) : a.week.localeCompare(b.week)));
  return rows;
}

// PR: e1rm válido estrictamente mayor al máximo e1rm válido histórico previo.
export function detectPr(e1rm: number | null, priorValidE1rms: number[]): boolean {
  if (e1rm === null) return false;
  if (priorValidE1rms.length === 0) return true;
  return e1rm > Math.max(...priorValidE1rms);
}
