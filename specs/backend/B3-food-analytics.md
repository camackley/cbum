# B3 — Resolución de alimentos + motor de análisis (Agente A)

**Prerrequisito:** B2. Este spec implementa el corazón del MUST de precisión. Los test vectors de contracts §5 son obligatorios.

## Parte 1 — Resolución de alimentos (`src/services/food.ts`)

### USDA FoodData Central (búsqueda por texto)
- `POST https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${FDC_API_KEY}` body `{"query", "dataType":["Foundation","SR Legacy","Branded"], "pageSize":10}`.
- Ranking de resultados: Foundation > SR Legacy > Branded para alimentos genéricos (pollo, arroz, huevo); mantener Branded cuando el query parece producto comercial.
- Normalizar SIEMPRE a **per 100 g**: mapear nutrientes por número FDC — energía 1008 (kcal), proteína 1003, carbohidratos 1005, grasa total 1004, fibra 1079. Si un item Branded trae `servingSize`, incluirla como dato informativo pero los macros retornados son per-100g.
- Retornar top N: `{fdc_id, description, data_type, per_100g:{kcal,protein_g,carbs_g,fat_g,fiber_g}}`.

### Open Food Facts (barcode)
- `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json?fields=product_name,brands,nutriments,serving_size`.
- Mapear `nutriments`: `energy-kcal_100g`, `proteins_100g`, `carbohydrates_100g`, `fat_100g`, `fiber_100g`. Si falta `energy-kcal_100g` pero hay `energy_100g` (kJ), convertir ÷ 4.184.
- Producto no encontrado o sin macros → respuesta explícita "no encontrado, pedir foto de la etiqueta"; **jamás** aproximar con otro producto.

### Reglas duras
- `resolve_food` nunca retorna macros sin `fdc_id`/`off_id` de respaldo.
- User-Agent identificable en llamadas a OFF (`cbum-personal/1.0`).
- Cachear respuestas en tabla `food_cache(key TEXT PRIMARY KEY, json TEXT, updated_at)` (key = `fdc:{id}` / `off:{barcode}` / `q:{hash del query}`) con TTL 30 días — reduce latencia y rate limits.

## Parte 2 — Motor de análisis (`src/services/analytics.ts` + `src/lib/formulas.ts`)

Funciones puras, testeables sin D1:
- `emaSeries(readings: {date,kg}[]): {date,ema}[]` — contracts §5.1 (promediar múltiples pesajes del mismo día antes de aplicar EMA; carry-forward en días sin dato).
- `adaptiveTdee(input): {kcal,status,window_days,complete_days_used,weighins_used}` — contracts §5.2, incluye fallback Mifflin con goals (sex, age, height_cm, activity_factor) usando trend actual como peso.
- `computeE1rm(weight,reps,rir,isWarmup)` — §5.3 (ya usada en B2).
- `suggestWeight(prescription, lastSessionSets, incrementKg)` — §5.4.
- `weeklyEffectiveSets(sets+exercises): [{week,muscle_group,effective_sets}]` — §5.5, semana ISO.
- `detectPr(exerciseId, e1rm, history): boolean` — §5.5.

Con esto, implementar los 4 endpoints stubbed en B2 (`summary/today`, `energy-status`, `progress`, `next-session`) con las shapes EXACTAS de contracts §3.1–3.4. `next-session` resuelve el día del schedule con la aritmética de contracts §4 (días entre start_date y date, módulo longitud del schedule; si cae "rest", retornar `{"program_day_id":"rest"}`).

## Tests (obligatorios — vitest)
`backend/test/formulas.test.ts` con TODOS los vectors de contracts §5:
1. EMA [80.0, 81.0, gap, 80.5] → [80.0, 80.1, 80.1, 80.14] (tolerancia 0.01).
2. TDEE: intake 2500, ΔEMA −0.6kg/21d → 2720.
3. TDEE con 9 días complete → status `calibrating` y valor Mifflin (verificar con: m, 30 años, 175cm, trend 82.4, factor 1.55 → Mifflin = 10×82.4+6.25×175−5×30+5 = 1772.75 → ×1.55 = 2747.8).
4. e1RM 100×8@2 → 133.3; 60×12@3 → null; warmup → null.
5. Sugerencia: 4×[6,8]@RIR2, inc 2.5, historia 4×80×8@2 → 82.5; con un set 80×7@2 → 80; sin historia → null.
6. PR: e1rm 133.3 con máximo previo 130 → true; 133.3 vs 133.3 → false.

## Aceptación
- `npm test` verde con los 6 grupos de vectors.
- `resolve_food` (vía tool en B4 o endpoint temporal de debug) retorna candidatos correctos para "chicken breast raw" (Foundation/SR Legacy primero) y para un barcode real de OFF.
- `energy-status` sobre DB con <10 días complete → `calibrating`.
