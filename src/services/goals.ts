import type { Env } from '../types';
import { now } from '../lib/time';

export type Goals = Record<string, string>;

export async function getGoals(env: Env): Promise<Goals> {
  const { results } = await env.DB.prepare(`SELECT key, value FROM goals`).all<{ key: string; value: string }>();
  const out: Goals = {};
  for (const r of results) out[r.key] = r.value;
  return out;
}

// Merge: cada key del payload se upsert-ea; las no incluidas se conservan.
export async function putGoals(env: Env, goals: Goals): Promise<Goals> {
  const ts = now();
  const entries = Object.entries(goals);
  if (entries.length > 0) {
    const sql = `INSERT INTO goals (key, value, updated_at) VALUES (?,?,?)
      ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at`;
    await env.DB.batch(entries.map(([k, v]) => env.DB.prepare(sql).bind(k, v, ts)));
  }
  return getGoals(env);
}
