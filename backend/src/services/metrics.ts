import type { Env } from '../types';
import { now } from '../lib/time';
import type { MetricInput } from '../lib/schemas';

export interface MetricRow {
  id: string;
  ts: string;
  date: string;
  type: string;
  value: number;
  source: string;
  updated_at: number;
  deleted: number;
}

const COLS = 'id, ts, date, type, value, source, updated_at, deleted';

// Upsert por (type,ts,source) — dedup de re-sync HealthKit (contracts §1).
// La tabla tiene DOS constraints: PK(id) y UNIQUE(type,ts,source). Un ON CONFLICT
// solo cubre uno; si el mismo id llega con otra tupla (ej. editar la hora de un pesaje)
// se violaría el PK → 500. Por eso: DELETE por id (limpia la fila vieja de ese id) +
// INSERT ON CONFLICT(tuple) (dedup de re-sync; conserva el id existente en colisión de tupla).
export async function upsertBodyMetrics(env: Env, metrics: MetricInput[]): Promise<number> {
  const ts = now();
  const insertSql = `INSERT INTO body_metrics (${COLS}) VALUES (?,?,?,?,?,?,?,?)
    ON CONFLICT(type, ts, source) DO UPDATE SET
      date=excluded.date, value=excluded.value, updated_at=excluded.updated_at, deleted=0`;
  const stmts: D1PreparedStatement[] = [];
  for (const m of metrics) {
    stmts.push(env.DB.prepare(`DELETE FROM body_metrics WHERE id=?`).bind(m.id));
    stmts.push(env.DB.prepare(insertSql).bind(m.id, m.ts, m.date, m.type, m.value, m.source, ts, 0));
  }
  if (stmts.length > 0) await env.DB.batch(stmts);
  return metrics.length;
}

export async function getBodyMetrics(
  env: Env,
  opts: { type?: string; from?: string; to?: string },
): Promise<MetricRow[]> {
  const clauses: string[] = ['deleted=0'];
  const binds: unknown[] = [];
  if (opts.type) {
    clauses.push('type=?');
    binds.push(opts.type);
  }
  if (opts.from) {
    clauses.push('date >= ?');
    binds.push(opts.from);
  }
  if (opts.to) {
    clauses.push('date <= ?');
    binds.push(opts.to);
  }
  const { results } = await env.DB.prepare(
    `SELECT ${COLS} FROM body_metrics WHERE ${clauses.join(' AND ')} ORDER BY ts ASC`,
  )
    .bind(...binds)
    .all<MetricRow>();
  return results;
}
