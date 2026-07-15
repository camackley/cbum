import type { Env } from '../types';
import { now } from '../lib/time';
import { unprocessable } from '../lib/errors';

export type Goals = Record<string, string>;

// Keys válidas (contracts §1). Se validan tipo/rango para que el TDEE/targets no consuman basura.
const NUMERIC_KEYS = new Set(['target_kcal', 'target_protein_g', 'target_carbs_g', 'target_fat_g', 'goal_weight_kg', 'goal_rate_kg_per_week', 'age', 'height_cm', 'activity_factor']);
const KNOWN_KEYS = new Set([...NUMERIC_KEYS, 'sex']);

function validateGoals(goals: Goals): void {
  for (const [k, v] of Object.entries(goals)) {
    if (!KNOWN_KEYS.has(k)) throw unprocessable(`goal key desconocida: '${k}'. Válidas: ${[...KNOWN_KEYS].join(', ')}`);
    if (k === 'sex') {
      if (v !== 'm' && v !== 'f') throw unprocessable("sex debe ser 'm' o 'f'");
      continue;
    }
    const n = parseFloat(v);
    if (!Number.isFinite(n)) throw unprocessable(`${k} debe ser numérico (recibí '${v}')`);
    if (k === 'activity_factor' && (n < 1.2 || n > 1.9)) throw unprocessable('activity_factor debe estar entre 1.2 y 1.9 (contracts §1)');
    if ((k === 'age' || k === 'height_cm' || k === 'goal_weight_kg') && n <= 0) throw unprocessable(`${k} debe ser > 0`);
  }
}

export async function getGoals(env: Env): Promise<Goals> {
  const { results } = await env.DB.prepare(`SELECT key, value FROM goals`).all<{ key: string; value: string }>();
  const out: Goals = {};
  for (const r of results) out[r.key] = r.value;
  return out;
}

// Merge: cada key del payload se upsert-ea; las no incluidas se conservan.
export async function putGoals(env: Env, goals: Goals): Promise<Goals> {
  validateGoals(goals);
  const ts = now();
  const entries = Object.entries(goals);
  if (entries.length > 0) {
    const sql = `INSERT INTO goals (key, value, updated_at) VALUES (?,?,?)
      ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at`;
    await env.DB.batch(entries.map(([k, v]) => env.DB.prepare(sql).bind(k, v, ts)));
  }
  return getGoals(env);
}
