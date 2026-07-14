import type { Env } from '../types';
import { now } from '../lib/time';

export interface DayFlagRow {
  date: string;
  logging_complete: number;
  updated_at: number;
}

export async function putDay(env: Env, date: string, loggingComplete: boolean): Promise<void> {
  const ts = now();
  await env.DB.prepare(
    `INSERT INTO day_flags (date, logging_complete, updated_at) VALUES (?,?,?)
     ON CONFLICT(date) DO UPDATE SET logging_complete=excluded.logging_complete, updated_at=excluded.updated_at`,
  )
    .bind(date, loggingComplete ? 1 : 0, ts)
    .run();
}

export async function getDayFlag(env: Env, date: string): Promise<DayFlagRow | null> {
  return env.DB.prepare(`SELECT date, logging_complete, updated_at FROM day_flags WHERE date=?`)
    .bind(date)
    .first<DayFlagRow>();
}

// Fechas con logging_complete=1 dentro de un rango (para TDEE).
export async function completeDaysInRange(env: Env, from: string, to: string): Promise<Set<string>> {
  const { results } = await env.DB.prepare(
    `SELECT date FROM day_flags WHERE logging_complete=1 AND date >= ? AND date <= ?`,
  )
    .bind(from, to)
    .all<{ date: string }>();
  return new Set(results.map((r) => r.date));
}
