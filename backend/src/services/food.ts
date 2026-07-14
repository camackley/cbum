import type { Env } from '../types';
import { now } from '../lib/time';
import { parseJson } from '../lib/db';

// Resolución de alimentos con macros REALES (contracts §6 / B3 parte 1).
// NUNCA se inventan macros: todo candidato lleva fdc_id (USDA) u off_id (Open Food Facts).

const CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 días
const OFF_USER_AGENT = 'cbum-personal/1.0';

export interface FoodCandidate {
  fdc_id?: number;
  off_id?: string;
  description: string;
  data_type: string;
  brand?: string;
  serving_size?: string | null;
  per_100g: { kcal: number; protein_g: number; carbs_g: number; fat_g: number; fiber_g: number | null };
}
export interface ResolveResult {
  found: boolean;
  source: 'usda' | 'off' | null;
  candidates: FoodCandidate[];
  message?: string;
}

// ── Cache ─────────────────────────────────────────────────────────────────────
async function cacheGet<T>(env: Env, key: string): Promise<T | null> {
  const row = await env.DB.prepare(`SELECT json, updated_at FROM food_cache WHERE key=?`).bind(key).first<{ json: string; updated_at: number }>();
  if (!row) return null;
  if (now() - row.updated_at > CACHE_TTL_MS) return null; // expirado
  return parseJson<T | null>(row.json, null);
}
async function cacheSet(env: Env, key: string, value: unknown): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO food_cache (key, json, updated_at) VALUES (?,?,?) ON CONFLICT(key) DO UPDATE SET json=excluded.json, updated_at=excluded.updated_at`,
  )
    .bind(key, JSON.stringify(value), now())
    .run();
}

// Hash estable simple (djb2) para keys de query.
function hashQuery(q: string): string {
  let h = 5381;
  const s = q.trim().toLowerCase();
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return (h >>> 0).toString(36);
}

// ── USDA FoodData Central (búsqueda por texto) ───────────────────────────────
// Ranking: Foundation > SR Legacy > Branded para genéricos; Branded se mantiene si el query parece marca.
const DATA_TYPE_RANK: Record<string, number> = { Foundation: 0, 'SR Legacy': 1, Branded: 2 };
const FDC_NUTRIENT = { kcal: 1008, protein: 1003, carbs: 1005, fat: 1004, fiber: 1079 };

function mapFdcFood(food: any): FoodCandidate | null {
  const nutrients: Record<number, number> = {};
  for (const n of food.foodNutrients ?? []) {
    const id = n.nutrientId ?? n.nutrient?.id;
    const val = n.value ?? n.amount;
    if (id != null && val != null) nutrients[id] = val;
  }
  const kcal = nutrients[FDC_NUTRIENT.kcal];
  if (kcal == null) return null; // sin energía no sirve
  return {
    fdc_id: food.fdcId,
    description: food.description ?? 'sin nombre',
    data_type: food.dataType ?? 'unknown',
    brand: food.brandOwner ?? food.brandName ?? undefined,
    serving_size: food.servingSize != null ? `${food.servingSize} ${food.servingSizeUnit ?? ''}`.trim() : null,
    per_100g: {
      kcal,
      protein_g: nutrients[FDC_NUTRIENT.protein] ?? 0,
      carbs_g: nutrients[FDC_NUTRIENT.carbs] ?? 0,
      fat_g: nutrients[FDC_NUTRIENT.fat] ?? 0,
      fiber_g: nutrients[FDC_NUTRIENT.fiber] ?? null,
    },
  };
}

export async function searchUsda(env: Env, query: string, pageSize = 5): Promise<ResolveResult> {
  const cacheKey = `q:${hashQuery(query)}:${pageSize}`;
  const cached = await cacheGet<ResolveResult>(env, cacheKey);
  if (cached) return cached;

  if (!env.FDC_API_KEY) {
    return { found: false, source: null, candidates: [], message: 'FDC_API_KEY no configurada en el server.' };
  }

  const url = `https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${encodeURIComponent(env.FDC_API_KEY)}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, dataType: ['Foundation', 'SR Legacy', 'Branded'], pageSize: 10 }),
  });
  if (!res.ok) {
    return { found: false, source: 'usda', candidates: [], message: `USDA FDC respondió ${res.status}.` };
  }
  const data: any = await res.json();
  const foods: any[] = data.foods ?? [];
  const mapped = foods.map(mapFdcFood).filter((f): f is FoodCandidate => f !== null);

  // Ordenar por rank de dataType (Foundation/SR Legacy primero), preservando orden de relevancia dentro del mismo tipo.
  mapped.sort((a, b) => (DATA_TYPE_RANK[a.data_type] ?? 3) - (DATA_TYPE_RANK[b.data_type] ?? 3));
  const candidates = mapped.slice(0, pageSize);

  const result: ResolveResult = candidates.length
    ? { found: true, source: 'usda', candidates }
    : { found: false, source: 'usda', candidates: [], message: `Sin resultados en USDA para "${query}". Pide la etiqueta nutricional y regístrala como source='label'.` };

  await cacheSet(env, cacheKey, result);
  return result;
}

// ── Open Food Facts (barcode) ────────────────────────────────────────────────
export async function lookupBarcode(env: Env, barcode: string): Promise<ResolveResult> {
  const cacheKey = `off:${barcode}`;
  const cached = await cacheGet<ResolveResult>(env, cacheKey);
  if (cached) return cached;

  const url = `https://world.openfoodfacts.org/api/v2/product/${encodeURIComponent(barcode)}.json?fields=product_name,brands,nutriments,serving_size`;
  const res = await fetch(url, { headers: { 'User-Agent': OFF_USER_AGENT } });
  if (!res.ok) {
    return { found: false, source: 'off', candidates: [], message: `Open Food Facts respondió ${res.status}.` };
  }
  const data: any = await res.json();
  const notFound: ResolveResult = {
    found: false,
    source: 'off',
    candidates: [],
    message: `Barcode ${barcode} no encontrado o sin macros en Open Food Facts. Pide foto de la etiqueta; NUNCA aproximar con otro producto.`,
  };
  if (data.status !== 1 || !data.product) {
    await cacheSet(env, cacheKey, notFound);
    return notFound;
  }

  const n = data.product.nutriments ?? {};
  let kcal = n['energy-kcal_100g'];
  if (kcal == null && n['energy_100g'] != null) kcal = n['energy_100g'] / 4.184; // kJ → kcal
  if (kcal == null) {
    await cacheSet(env, cacheKey, notFound);
    return notFound;
  }

  const candidate: FoodCandidate = {
    off_id: barcode,
    description: data.product.product_name || `Producto ${barcode}`,
    data_type: 'off_barcode',
    brand: data.product.brands || undefined,
    serving_size: data.product.serving_size ?? null,
    per_100g: {
      kcal: round2(kcal),
      protein_g: n['proteins_100g'] ?? 0,
      carbs_g: n['carbohydrates_100g'] ?? 0,
      fat_g: n['fat_100g'] ?? 0,
      fiber_g: n['fiber_100g'] ?? null,
    },
  };
  const result: ResolveResult = { found: true, source: 'off', candidates: [candidate] };
  await cacheSet(env, cacheKey, result);
  return result;
}

function round2(x: number): number {
  return Math.round(x * 100) / 100;
}

// ── Entrada unificada (tool resolve_food) ────────────────────────────────────
export async function resolveFood(
  env: Env,
  input: { query?: string; barcode?: string; page_size?: number },
): Promise<ResolveResult> {
  if (input.barcode) return lookupBarcode(env, input.barcode);
  if (input.query) return searchUsda(env, input.query, input.page_size ?? 5);
  return { found: false, source: null, candidates: [], message: 'Provee query (nombre) o barcode.' };
}
