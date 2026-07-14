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
export async function upsertBodyMetrics(env: Env, metrics: MetricInput[]): Promise<number> {
  const ts = now();
  const sql = `INSERT INTO body_metrics (${COLS}) VALUES (?,?,?,?,?,?,?,?)
    ON CONFLICT(type, ts, source) DO UPDATE SET
      date=excluded.date, value=excluded.value, updated_at=excluded.updated_at, deleted=0`;
  const stmts = metrics.map((m) =>
    env.DB.prepare(sql).bind(m.id, m.ts, m.date, m.type, m.value, m.source, ts, 0),
  );
  if (stmts.length > 0) await env.DB.batch(stmts);
  return stmts.length;
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
