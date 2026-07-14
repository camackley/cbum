import type { Env } from '../types';
import { now } from '../lib/time';
import { computeE1rm } from '../lib/formulas';
import { notFound, unprocessable } from '../lib/errors';
import type { WorkoutInput } from '../lib/schemas';

export interface SetRow {
  id: string;
  workout_id: string;
  exercise_id: string;
  set_number: number;
  weight_kg: number;
  reps: number;
  rir: number;
  is_warmup: number;
  e1rm_kg: number | null;
  updated_at: number;
  deleted: number;
}
export interface WorkoutRow {
  id: string;
  ts_start: string;
  ts_end: string | null;
  date: string;
  program_day_id: string | null;
  notes: string | null;
  updated_at: number;
  deleted: number;
  sets: SetRow[];
}

const W_COLS = 'id, ts_start, ts_end, date, program_day_id, notes, updated_at, deleted';
const S_COLS = 'id, workout_id, exercise_id, set_number, weight_kg, reps, rir, is_warmup, e1rm_kg, updated_at, deleted';

async function assertExercisesExist(env: Env, ids: string[]): Promise<void> {
  const unique = [...new Set(ids)];
  if (unique.length === 0) return;
  const placeholders = unique.map(() => '?').join(',');
  const { results } = await env.DB.prepare(
    `SELECT id FROM exercises WHERE deleted=0 AND id IN (${placeholders})`,
  )
    .bind(...unique)
    .all<{ id: string }>();
  const found = new Set(results.map((r) => r.id));
  const missing = unique.filter((id) => !found.has(id));
  if (missing.length > 0) {
    throw unprocessable(`exercise_id inexistente en el catálogo: ${missing.join(', ')}`);
  }
}

// Upsert transaccional: workout + sets con e1rm calculado por el server (§5.3).
export async function upsertWorkout(env: Env, w: WorkoutInput): Promise<WorkoutRow> {
  await assertExercisesExist(env, w.sets.map((s) => s.exercise_id));
  const ts = now();

  const workoutSql = `INSERT INTO workouts (${W_COLS}) VALUES (?,?,?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET
      ts_start=excluded.ts_start, ts_end=excluded.ts_end, date=excluded.date,
      program_day_id=excluded.program_day_id, notes=excluded.notes, updated_at=excluded.updated_at, deleted=0`;

  const setSql = `INSERT INTO sets (${S_COLS}) VALUES (?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET
      workout_id=excluded.workout_id, exercise_id=excluded.exercise_id, set_number=excluded.set_number,
      weight_kg=excluded.weight_kg, reps=excluded.reps, rir=excluded.rir, is_warmup=excluded.is_warmup,
      e1rm_kg=excluded.e1rm_kg, updated_at=excluded.updated_at, deleted=0`;

  const stmts = [
    env.DB.prepare(workoutSql).bind(
      w.id, w.ts_start, w.ts_end ?? null, w.date, w.program_day_id ?? null, w.notes ?? null, ts, 0,
    ),
    ...w.sets.map((s) => {
      const e1rm = computeE1rm(s.weight_kg, s.reps, s.rir, s.is_warmup);
      return env.DB.prepare(setSql).bind(
        s.id, w.id, s.exercise_id, s.set_number, s.weight_kg, s.reps, s.rir, s.is_warmup ? 1 : 0, e1rm, ts, 0,
      );
    }),
  ];
  await env.DB.batch(stmts);

  const result = await getWorkoutById(env, w.id);
  if (!result) throw notFound('Workout no encontrado tras upsert');
  return result;
}

export async function getWorkoutById(env: Env, id: string): Promise<WorkoutRow | null> {
  const w = await env.DB.prepare(`SELECT ${W_COLS} FROM workouts WHERE id=?`).bind(id).first<Omit<WorkoutRow, 'sets'>>();
  if (!w) return null;
  const { results: sets } = await env.DB.prepare(
    `SELECT ${S_COLS} FROM sets WHERE workout_id=? AND deleted=0 ORDER BY set_number ASC`,
  )
    .bind(id)
    .all<SetRow>();
  return { ...w, sets };
}

export async function getWorkouts(
  env: Env,
  opts: { from?: string; to?: string; exercise_id?: string },
): Promise<WorkoutRow[]> {
  const clauses: string[] = ['w.deleted=0'];
  const binds: unknown[] = [];
  if (opts.from) {
    clauses.push('w.date >= ?');
    binds.push(opts.from);
  }
  if (opts.to) {
    clauses.push('w.date <= ?');
    binds.push(opts.to);
  }
  if (opts.exercise_id) {
    clauses.push('EXISTS (SELECT 1 FROM sets s WHERE s.workout_id=w.id AND s.deleted=0 AND s.exercise_id=?)');
    binds.push(opts.exercise_id);
  }
  const { results: workouts } = await env.DB.prepare(
    `SELECT ${W_COLS.split(', ').map((c) => `w.${c}`).join(', ')} FROM workouts w WHERE ${clauses.join(' AND ')} ORDER BY w.ts_start DESC`,
  )
    .bind(...binds)
    .all<Omit<WorkoutRow, 'sets'>>();

  const out: WorkoutRow[] = [];
  for (const w of workouts) {
    const { results: sets } = await env.DB.prepare(
      `SELECT ${S_COLS} FROM sets WHERE workout_id=? AND deleted=0 ORDER BY set_number ASC`,
    )
      .bind(w.id)
      .all<SetRow>();
    out.push({ ...w, sets });
  }
  return out;
}

export async function deleteWorkout(env: Env, id: string): Promise<void> {
  const ts = now();
  const res = await env.DB.batch([
    env.DB.prepare(`UPDATE workouts SET deleted=1, updated_at=? WHERE id=? AND deleted=0`).bind(ts, id),
    env.DB.prepare(`UPDATE sets SET deleted=1, updated_at=? WHERE workout_id=?`).bind(ts, id),
  ]);
  if (!res[0]!.meta.changes) throw notFound('Workout no encontrado');
}
