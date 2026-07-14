import type { Env } from '../types';
import { now } from '../lib/time';
import type { ExerciseInput } from '../lib/schemas';

export interface ExerciseRow {
  id: string;
  name: string;
  muscle_group: string;
  pattern: string;
  equipment: string;
  increment_kg: number;
  updated_at: number;
  deleted: number;
}

const COLS = 'id, name, muscle_group, pattern, equipment, increment_kg, updated_at, deleted';

export async function getExercises(env: Env): Promise<ExerciseRow[]> {
  const { results } = await env.DB.prepare(
    `SELECT ${COLS} FROM exercises WHERE deleted=0 ORDER BY muscle_group, name`,
  ).all<ExerciseRow>();
  return results;
}

export async function upsertExercises(env: Env, exercises: ExerciseInput[]): Promise<number> {
  const ts = now();
  const sql = `INSERT INTO exercises (${COLS}) VALUES (?,?,?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET
      name=excluded.name, muscle_group=excluded.muscle_group, pattern=excluded.pattern,
      equipment=excluded.equipment, increment_kg=excluded.increment_kg, updated_at=excluded.updated_at, deleted=0`;
  const stmts = exercises.map((e) =>
    env.DB.prepare(sql).bind(e.id, e.name, e.muscle_group, e.pattern, e.equipment, e.increment_kg, ts, 0),
  );
  if (stmts.length > 0) await env.DB.batch(stmts);
  return stmts.length;
}

// Mapa id → increment_kg (para sugerencias). Incluye todos los no borrados.
export async function exerciseMap(env: Env): Promise<Map<string, ExerciseRow>> {
  const rows = await getExercises(env);
  return new Map(rows.map((r) => [r.id, r]));
}
