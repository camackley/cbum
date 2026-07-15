import type { Env } from '../types';
import { now } from '../lib/time';
import { parseJson } from '../lib/db';

// GET /api/changes?since=<epoch_ms>. Pull incremental: cada tabla WHERE updated_at > since.
// Incluye deleted=1 para que iOS borre local. cursor = now() al inicio del request.
export interface ChangesResult {
  cursor: number;
  meals: unknown[];
  workouts: unknown[];
  sets: unknown[];
  body_metrics: unknown[];
  exercises: unknown[];
  program: unknown[];
  goals: unknown[];
  day_flags: unknown[];
}

// Margen de seguridad: un write concurrente puede sellar updated_at justo antes del
// cursor y commitear después de las lecturas → se perdería para siempre. Restar un
// margen re-entrega una ventana pequeña en el siguiente pull (idempotente: iOS upsert por id).
const CURSOR_SAFETY_MS = 2000;

export async function getChanges(env: Env, since: number): Promise<ChangesResult> {
  const cursor = Math.max(0, now() - CURSOR_SAFETY_MS);

  const mealsRaw = await env.DB.prepare(`SELECT * FROM meals WHERE updated_at > ?`).bind(since).all<Record<string, unknown>>();
  const meals = mealsRaw.results.map((m) => ({ ...m, per_100g: parseJson(m.per_100g as string | null, null) }));

  // sets cambiados y sus workouts padre (aunque el workout no haya cambiado).
  const setsRes = await env.DB.prepare(`SELECT * FROM sets WHERE updated_at > ?`).bind(since).all<Record<string, unknown>>();
  const sets = setsRes.results;
  const parentIds = [...new Set(sets.map((s) => s.workout_id as string))];

  let workouts: Record<string, unknown>[];
  if (parentIds.length > 0) {
    const ph = parentIds.map(() => '?').join(',');
    const wr = await env.DB.prepare(`SELECT * FROM workouts WHERE updated_at > ? OR id IN (${ph})`)
      .bind(since, ...parentIds)
      .all<Record<string, unknown>>();
    workouts = wr.results;
  } else {
    const wr = await env.DB.prepare(`SELECT * FROM workouts WHERE updated_at > ?`).bind(since).all<Record<string, unknown>>();
    workouts = wr.results;
  }

  const bm = await env.DB.prepare(`SELECT * FROM body_metrics WHERE updated_at > ?`).bind(since).all();
  const ex = await env.DB.prepare(`SELECT * FROM exercises WHERE updated_at > ?`).bind(since).all();
  const prog = await env.DB.prepare(`SELECT * FROM program WHERE updated_at > ?`).bind(since).all();
  const goals = await env.DB.prepare(`SELECT * FROM goals WHERE updated_at > ?`).bind(since).all();
  const flags = await env.DB.prepare(`SELECT * FROM day_flags WHERE updated_at > ?`).bind(since).all();

  return {
    cursor,
    meals,
    workouts,
    sets,
    body_metrics: bm.results,
    exercises: ex.results,
    program: prog.results,
    goals: goals.results,
    day_flags: flags.results,
  };
}
