import type { Env } from '../types';
import { now } from '../lib/time';

// GET /api/export: dump JSON completo de todas las tablas (incl. deleted).
export async function exportAll(env: Env): Promise<Record<string, unknown>> {
  const tables = ['meals', 'exercises', 'workouts', 'sets', 'body_metrics', 'day_flags', 'program', 'goals'];
  const out: Record<string, unknown> = { exported_at: now() };
  for (const t of tables) {
    const { results } = await env.DB.prepare(`SELECT * FROM ${t}`).all();
    out[t] = results;
  }
  return out;
}
