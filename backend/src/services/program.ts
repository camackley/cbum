import type { Env } from '../types';
import { now } from '../lib/time';
import { parseJson } from '../lib/db';
import { unprocessable } from '../lib/errors';
import { randomUuid } from '../lib/uuid';
import { programPutSchema, type ProgramJson } from '../lib/schemas';
import { validate } from '../lib/validate';
import { getExercises } from './exercises';

export interface ProgramRow {
  id: string;
  active: number;
  start_date: string;
  json: ProgramJson;
  updated_at: number;
  deleted: number;
}

// Valida §4 contra el catálogo. Lanza 422 con detalle. Devuelve el json validado.
export async function validateProgram(env: Env, json: ProgramJson): Promise<void> {
  const catalog = await getExercises(env);
  const validIds = new Set(catalog.map((e) => e.id));

  const dayIds = new Set(json.days.map((d) => d.id));

  // Todo exercise_id debe existir en el catálogo.
  const missing = new Set<string>();
  for (const day of json.days) {
    for (const ex of day.exercises) {
      if (!validIds.has(ex.exercise_id)) missing.add(ex.exercise_id);
    }
  }
  if (missing.size > 0) {
    throw unprocessable(
      `exercise_id inexistente en el catálogo: ${[...missing].join(', ')}. Ids válidos: ${[...validIds].join(', ')}`,
      'invalid_program',
    );
  }

  // Cada entrada del schedule debe ser 'rest' o un day-id definido.
  const badSchedule = json.schedule.filter((s) => s !== 'rest' && !dayIds.has(s));
  if (badSchedule.length > 0) {
    throw unprocessable(
      `schedule referencia day-ids inexistentes: ${[...new Set(badSchedule)].join(', ')}. Days definidos: ${[...dayIds].join(', ')}`,
      'invalid_program',
    );
  }

  // day ids únicos.
  if (dayIds.size !== json.days.length) {
    throw unprocessable('los ids de days deben ser únicos', 'invalid_program');
  }
}

export async function getActiveProgram(env: Env): Promise<ProgramRow | null> {
  const row = await env.DB.prepare(
    `SELECT id, active, start_date, json, updated_at, deleted FROM program WHERE active=1 AND deleted=0 ORDER BY updated_at DESC LIMIT 1`,
  ).first<{ id: string; active: number; start_date: string; json: string; updated_at: number; deleted: number }>();
  if (!row) return null;
  return { ...row, json: parseJson<ProgramJson>(row.json, {} as ProgramJson) };
}

// PUT: valida §4, desactiva el anterior, inserta el nuevo activo. Idempotente por contenido no,
// pero cada PUT crea un programa nuevo activo (histórico preservado como active=0).
export async function putProgram(env: Env, raw: unknown): Promise<ProgramRow> {
  const parsed = validate(programPutSchema, raw);
  await validateProgram(env, parsed.json);

  const ts = now();
  const id = randomUuid();
  await env.DB.batch([
    env.DB.prepare(`UPDATE program SET active=0, updated_at=? WHERE active=1 AND deleted=0`).bind(ts),
    env.DB.prepare(
      `INSERT INTO program (id, active, start_date, json, updated_at, deleted) VALUES (?,1,?,?,?,0)`,
    ).bind(id, parsed.start_date, JSON.stringify(parsed.json), ts),
  ]);

  const created = await getActiveProgram(env);
  return created!;
}
