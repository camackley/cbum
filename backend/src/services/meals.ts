import type { Env } from '../types';
import { now } from '../lib/time';
import { parseJson } from '../lib/db';
import { round1 } from '../lib/formulas';
import { notFound, unprocessable } from '../lib/errors';
import type { MealInput, Per100g } from '../lib/schemas';
import { mealPatchSchema } from '../lib/schemas';
import { validate } from '../lib/validate';
import { randomUuid } from '../lib/uuid';

export interface MealRow {
  id: string;
  ts: string;
  date: string;
  meal_group_id: string;
  name: string;
  quantity_g: number | null;
  kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  fiber_g: number | null;
  per_100g: Per100g | null;
  source: string;
  confidence: number;
  portion_basis: string;
  fdc_id: number | null;
  off_id: string | null;
  notes: string | null;
  updated_at: number;
  deleted: number;
}

interface RawMealRow extends Omit<MealRow, 'per_100g'> {
  per_100g: string | null;
}

function mapRow(r: RawMealRow): MealRow {
  return { ...r, per_100g: parseJson<Per100g | null>(r.per_100g, null) };
}

const COLS = 'id, ts, date, meal_group_id, name, quantity_g, kcal, protein_g, carbs_g, fat_g, fiber_g, per_100g, source, confidence, portion_basis, fdc_id, off_id, notes, updated_at, deleted';

// Upsert idempotente por id. Genera id/meal_group_id si faltan (path MCP).
export async function upsertMeals(env: Env, meals: MealInput[]): Promise<number> {
  const ts = now();
  const sql = `INSERT INTO meals (${COLS}) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET
      ts=excluded.ts, date=excluded.date, meal_group_id=excluded.meal_group_id, name=excluded.name,
      quantity_g=excluded.quantity_g, kcal=excluded.kcal, protein_g=excluded.protein_g, carbs_g=excluded.carbs_g,
      fat_g=excluded.fat_g, fiber_g=excluded.fiber_g, per_100g=excluded.per_100g, source=excluded.source,
      confidence=excluded.confidence, portion_basis=excluded.portion_basis, fdc_id=excluded.fdc_id,
      off_id=excluded.off_id, notes=excluded.notes, updated_at=excluded.updated_at, deleted=0`;

  const stmts = meals.map((m) => {
    const id = m.id ?? randomUuid();
    const groupId = m.meal_group_id ?? randomUuid();
    return env.DB.prepare(sql).bind(
      id, m.ts, m.date, groupId, m.name,
      m.quantity_g ?? null, m.kcal, m.protein_g, m.carbs_g, m.fat_g, m.fiber_g ?? null,
      m.per_100g ? JSON.stringify(m.per_100g) : null,
      m.source, m.confidence, m.portion_basis,
      m.fdc_id ?? null, m.off_id ?? null, m.notes ?? null, ts, 0,
    );
  });
  if (stmts.length > 0) await env.DB.batch(stmts);
  return stmts.length;
}

export async function getMeals(env: Env, from: string, to: string): Promise<MealRow[]> {
  const { results } = await env.DB.prepare(
    `SELECT ${COLS} FROM meals WHERE deleted=0 AND date >= ? AND date <= ? ORDER BY ts ASC`,
  )
    .bind(from, to)
    .all<RawMealRow>();
  return results.map(mapRow);
}

export async function getMealsByDate(env: Env, date: string): Promise<MealRow[]> {
  return getMeals(env, date, date);
}

export async function patchMeal(env: Env, id: string, patchRaw: unknown): Promise<MealRow> {
  const patch = validate(mealPatchSchema, patchRaw);
  const existing = await env.DB.prepare(`SELECT ${COLS} FROM meals WHERE id=? AND deleted=0`).bind(id).first<RawMealRow>();
  if (!existing) throw notFound('Meal no encontrado');
  const row = mapRow(existing);

  // Merge de campos.
  let { quantity_g, kcal, protein_g, carbs_g, fat_g, fiber_g, name, portion_basis, confidence, notes } = row;

  if (patch.quantity_g != null && row.per_100g) {
    // Recalcular macros desde per_100g × quantity_g/100 (redondeo 1 decimal).
    const p = row.per_100g;
    const f = patch.quantity_g / 100;
    quantity_g = patch.quantity_g;
    kcal = round1(p.kcal * f);
    protein_g = round1(p.protein_g * f);
    carbs_g = round1(p.carbs_g * f);
    fat_g = round1(p.fat_g * f);
    fiber_g = p.fiber_g != null ? round1(p.fiber_g * f) : fiber_g;
  } else if (patch.quantity_g != null && !row.per_100g) {
    // Sin per_100g no se puede recalcular por porción.
    throw unprocessable('No se puede recalcular por porción: el meal no tiene per_100g. Edita los macros directamente.');
  }

  if (patch.name !== undefined) name = patch.name;
  if (patch.kcal !== undefined) kcal = patch.kcal;
  if (patch.protein_g !== undefined) protein_g = patch.protein_g;
  if (patch.carbs_g !== undefined) carbs_g = patch.carbs_g;
  if (patch.fat_g !== undefined) fat_g = patch.fat_g;
  if (patch.fiber_g !== undefined) fiber_g = patch.fiber_g ?? null;
  if (patch.confidence !== undefined) confidence = patch.confidence;
  if (patch.notes !== undefined) notes = patch.notes ?? null;

  // Edición directa de macros sin per_100g → forzar estimated salvo que el request diga lo contrario.
  const editedMacrosDirectly =
    patch.kcal !== undefined || patch.protein_g !== undefined || patch.carbs_g !== undefined || patch.fat_g !== undefined;
  if (patch.portion_basis !== undefined) portion_basis = patch.portion_basis;
  else if (editedMacrosDirectly && !row.per_100g) portion_basis = 'estimated';

  const ts = now();
  await env.DB.prepare(
    `UPDATE meals SET quantity_g=?, kcal=?, protein_g=?, carbs_g=?, fat_g=?, fiber_g=?, name=?, portion_basis=?, confidence=?, notes=?, updated_at=? WHERE id=?`,
  )
    .bind(quantity_g, kcal, protein_g, carbs_g, fat_g, fiber_g, name, portion_basis, confidence, notes, ts, id)
    .run();

  const updated = await env.DB.prepare(`SELECT ${COLS} FROM meals WHERE id=?`).bind(id).first<RawMealRow>();
  return mapRow(updated!);
}

export async function deleteMeal(env: Env, id: string): Promise<void> {
  const res = await env.DB.prepare(`UPDATE meals SET deleted=1, updated_at=? WHERE id=? AND deleted=0`).bind(now(), id).run();
  if (!res.meta.changes) throw notFound('Meal no encontrado');
}
