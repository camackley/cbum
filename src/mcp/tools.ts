import type { Env } from '../types';
import { validate } from '../lib/validate';
import { unprocessable } from '../lib/errors';
import { todayBogota } from '../lib/time';
import { round1 } from '../lib/formulas';
import { randomUuid } from '../lib/uuid';
import {
  mealInputSchema,
  workoutInputSchema,
  goalsPutSchema,
  METRIC_TYPES,
  type MealInput,
} from '../lib/schemas';
import * as mealsSvc from '../services/meals';
import * as workoutsSvc from '../services/workouts';
import * as metricsSvc from '../services/metrics';
import * as goalsSvc from '../services/goals';
import * as daysSvc from '../services/days';
import * as programSvc from '../services/program';
import * as analytics from '../services/analytics';
import { resolveFood } from '../services/food';
import { emaSeries } from '../lib/formulas';

export interface McpTool {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  handler: (env: Env, args: any) => Promise<unknown>;
}

// Helpers de output ────────────────────────────────────────────────────────────
async function dayTotals(env: Env, date: string) {
  const meals = await mealsSvc.getMealsByDate(env, date);
  const totals = meals.reduce(
    (a, m) => ({
      kcal: a.kcal + m.kcal,
      protein_g: a.protein_g + m.protein_g,
      carbs_g: a.carbs_g + m.carbs_g,
      fat_g: a.fat_g + m.fat_g,
      fiber_g: a.fiber_g + (m.fiber_g ?? 0),
    }),
    { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 },
  );
  const goals = await goalsSvc.getGoals(env);
  const numOr = (v: string | undefined) => (v != null && Number.isFinite(parseFloat(v)) ? parseFloat(v) : null);
  const weighed = meals.filter((m) => m.portion_basis === 'weighed').length;
  return {
    date,
    items: meals.length,
    weighed_pct: meals.length ? round1(weighed / meals.length) : 0,
    totals: {
      kcal: round1(totals.kcal),
      protein_g: round1(totals.protein_g),
      carbs_g: round1(totals.carbs_g),
      fat_g: round1(totals.fat_g),
      fiber_g: round1(totals.fiber_g),
    },
    targets: {
      kcal: numOr(goals.target_kcal),
      protein_g: numOr(goals.target_protein_g),
      carbs_g: numOr(goals.target_carbs_g),
      fat_g: numOr(goals.target_fat_g),
    },
  };
}

// ── Registro de tools ─────────────────────────────────────────────────────────
export const TOOLS: McpTool[] = [
  {
    name: 'resolve_food',
    description:
      'SIEMPRE usar antes de log_meal para comida identificada por foto o nombre. Nunca estimes macros por tu cuenta. barcode → Open Food Facts; query (nombre) → USDA FoodData Central (prioriza Foundation/SR Legacy sobre Branded). Devuelve candidatos con macros per 100g + fdc_id/off_id. Si no hay match, dilo y pide la etiqueta nutricional.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Nombre del alimento en inglés para mejor cobertura USDA (ej. "chicken breast raw")' },
        barcode: { type: 'string', description: 'Código de barras (EAN/UPC) para Open Food Facts' },
        page_size: { type: 'number', description: 'Máx candidatos a devolver (default 5)', default: 5 },
      },
    },
    handler: (env, a) => resolveFood(env, { query: a.query, barcode: a.barcode, page_size: a.page_size }),
  },

  {
    name: 'log_meal',
    description:
      "Registra items YA resueltos con resolve_food. Regla dura: source='photo' exige fdc_id u off_id. Si la porción no fue pesada, portion_basis='estimated' y confidence honesta (<0.7 si hay duda real de cantidad). Genera ids/meal_group_id si faltan. Devuelve resumen + totales del día vs targets.",
    inputSchema: {
      type: 'object',
      required: ['ts', 'date', 'items'],
      properties: {
        ts: { type: 'string', description: 'ISO-8601 con offset, ej. 2026-07-14T13:30:00-05:00' },
        date: { type: 'string', description: 'YYYY-MM-DD (Bogotá)' },
        meal_group_id: { type: 'string', description: 'Opcional; agrupa los items de esta comida' },
        items: {
          type: 'array',
          minItems: 1,
          items: {
            type: 'object',
            required: ['name', 'kcal', 'protein_g', 'carbs_g', 'fat_g', 'source', 'confidence', 'portion_basis'],
            properties: {
              name: { type: 'string' },
              quantity_g: { type: 'number', description: 'Gramos consumidos; null si el registro es por totales de etiqueta' },
              per_100g: {
                type: 'object',
                description: 'Macros por 100g (de resolve_food); permite recalcular al editar porción',
                properties: {
                  kcal: { type: 'number' }, protein_g: { type: 'number' }, carbs_g: { type: 'number' },
                  fat_g: { type: 'number' }, fiber_g: { type: 'number' },
                },
              },
              kcal: { type: 'number' }, protein_g: { type: 'number' }, carbs_g: { type: 'number' },
              fat_g: { type: 'number' }, fiber_g: { type: 'number' },
              source: { type: 'string', enum: ['label', 'barcode', 'photo', 'manual'] },
              confidence: { type: 'number', minimum: 0, maximum: 1 },
              portion_basis: { type: 'string', enum: ['weighed', 'estimated'] },
              fdc_id: { type: 'number' }, off_id: { type: 'string' },
              notes: { type: 'string' },
            },
          },
        },
      },
    },
    handler: async (env, a) => {
      if (!a?.items?.length) throw unprocessable('log_meal requiere al menos un item');
      const groupId = a.meal_group_id ?? randomUuid();
      const meals: MealInput[] = a.items.map((it: any) =>
        validate(mealInputSchema, {
          ...it,
          id: it.id ?? randomUuid(),
          ts: a.ts,
          date: a.date,
          meal_group_id: groupId,
        }),
      );
      const upserted = await mealsSvc.upsertMeals(env, meals);
      const summary = await dayTotals(env, a.date);
      return { upserted, meal_group_id: groupId, day: summary };
    },
  },

  {
    name: 'get_meals',
    description: 'Meals en un rango de fechas, agrupados por día con totales y % de porciones pesadas.',
    inputSchema: {
      type: 'object',
      required: ['from', 'to'],
      properties: {
        from: { type: 'string', description: 'YYYY-MM-DD' },
        to: { type: 'string', description: 'YYYY-MM-DD' },
      },
    },
    handler: async (env, a) => {
      const meals = await mealsSvc.getMeals(env, a.from, a.to);
      const byDay = new Map<string, typeof meals>();
      for (const m of meals) {
        const arr = byDay.get(m.date) ?? [];
        arr.push(m);
        byDay.set(m.date, arr);
      }
      const days = [...byDay.entries()].map(([date, ms]) => {
        const t = ms.reduce(
          (a2, m) => ({
            kcal: a2.kcal + m.kcal, protein_g: a2.protein_g + m.protein_g,
            carbs_g: a2.carbs_g + m.carbs_g, fat_g: a2.fat_g + m.fat_g, fiber_g: a2.fiber_g + (m.fiber_g ?? 0),
          }),
          { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 },
        );
        const weighed = ms.filter((m) => m.portion_basis === 'weighed').length;
        return {
          date,
          totals: {
            kcal: round1(t.kcal), protein_g: round1(t.protein_g), carbs_g: round1(t.carbs_g),
            fat_g: round1(t.fat_g), fiber_g: round1(t.fiber_g),
          },
          weighed_pct: ms.length ? round1(weighed / ms.length) : 0,
          items: ms.map((m) => ({
            name: m.name, quantity_g: m.quantity_g, kcal: m.kcal, protein_g: m.protein_g,
            source: m.source, portion_basis: m.portion_basis, confidence: m.confidence,
          })),
        };
      });
      days.sort((a2, b2) => a2.date.localeCompare(b2.date));
      return { days };
    },
  },

  {
    name: 'get_workouts',
    description: 'Workouts en un rango con sets, e1RM calculado y PRs. Filtra por exercise_id opcional.',
    inputSchema: {
      type: 'object',
      required: ['from', 'to'],
      properties: {
        from: { type: 'string', description: 'YYYY-MM-DD' },
        to: { type: 'string', description: 'YYYY-MM-DD' },
        exercise_id: { type: 'string', description: 'Opcional: solo workouts que incluyen este ejercicio' },
      },
    },
    handler: (env, a) => workoutsSvc.getWorkouts(env, { from: a.from, to: a.to, exercise_id: a.exercise_id }),
  },

  {
    name: 'get_body_metrics',
    description: 'Serie cruda de una métrica corporal en un rango. Para weight_kg incluye además la serie EMA (tendencia).',
    inputSchema: {
      type: 'object',
      required: ['type', 'from', 'to'],
      properties: {
        type: { type: 'string', enum: [...METRIC_TYPES] },
        from: { type: 'string', description: 'YYYY-MM-DD' },
        to: { type: 'string', description: 'YYYY-MM-DD' },
      },
    },
    handler: async (env, a) => {
      const metrics = await metricsSvc.getBodyMetrics(env, { type: a.type, from: a.from, to: a.to });
      const out: Record<string, unknown> = {
        type: a.type,
        series: metrics.map((m) => ({ date: m.date, ts: m.ts, value: m.value, source: m.source })),
      };
      if (a.type === 'weight_kg') {
        out.ema_series = emaSeries(metrics.map((m) => ({ date: m.date, kg: m.value }))).map((p) => ({
          date: p.date,
          ema_kg: round1(p.ema),
        }));
      }
      return out;
    },
  },

  {
    name: 'get_progress',
    description: 'Volumen semanal por grupo muscular (sets efectivos) + PRs recientes. Con exercise_id: serie e1RM por sesión y mejores sets.',
    inputSchema: {
      type: 'object',
      properties: { exercise_id: { type: 'string', description: 'Opcional: detalle de un ejercicio' } },
    },
    handler: (env, a) => analytics.progress(env, a?.exercise_id),
  },

  {
    name: 'get_energy_status',
    description: 'TDEE adaptativo actual (o calibrating con Mifflin si falta data), tendencia de peso, adherencia y ritmo vs objetivo. Base para ajustar calorías SOLO con ≥14 días de data.',
    inputSchema: { type: 'object', properties: {} },
    handler: (env) => analytics.energyStatus(env),
  },

  {
    name: 'get_program',
    description: 'Programa de entrenamiento activo y qué día del schedule toca hoy (con sugerencias de peso por ejercicio).',
    inputSchema: { type: 'object', properties: {} },
    handler: async (env) => {
      const program = await programSvc.getActiveProgram(env);
      const today = todayBogota();
      const session = await analytics.nextSession(env, today);
      return {
        program: program ? { id: program.id, start_date: program.start_date, json: program.json } : null,
        today: { date: today, ...session },
      };
    },
  },

  {
    name: 'update_program',
    description:
      'Reemplaza el programa activo. Valida §4: cada exercise_id debe existir en el catálogo (si falla, devuelve la lista de ids válidos), rep_range=[min,max] con min≤max, schedule = ciclo de day-ids o "rest". Nunca ajustes el programa sin mirar get_progress primero.',
    inputSchema: {
      type: 'object',
      required: ['start_date', 'json'],
      properties: {
        start_date: { type: 'string', description: 'YYYY-MM-DD; ancla el schedule' },
        json: {
          type: 'object',
          required: ['version', 'name', 'days', 'schedule'],
          properties: {
            version: { type: 'number' },
            name: { type: 'string' },
            days: {
              type: 'array',
              items: {
                type: 'object',
                required: ['id', 'name', 'exercises'],
                properties: {
                  id: { type: 'string' },
                  name: { type: 'string' },
                  exercises: {
                    type: 'array',
                    items: {
                      type: 'object',
                      required: ['exercise_id', 'sets', 'rep_range', 'target_rir', 'rest_sec'],
                      properties: {
                        exercise_id: { type: 'string' },
                        sets: { type: 'number' },
                        rep_range: { type: 'array', items: { type: 'number' }, minItems: 2, maxItems: 2 },
                        target_rir: { type: 'number', minimum: 0, maximum: 5 },
                        rest_sec: { type: 'number' },
                        notes: { type: 'string' },
                      },
                    },
                  },
                },
              },
            },
            schedule: { type: 'array', items: { type: 'string' }, description: 'day-ids o "rest", repetido en ciclo' },
          },
        },
      },
    },
    handler: async (env, a) => {
      const program = await programSvc.putProgram(env, { start_date: a.start_date, json: a.json });
      return { program: { id: program.id, start_date: program.start_date, json: program.json } };
    },
  },

  {
    name: 'get_goals',
    description: 'Objetivos actuales (macros, peso meta, ritmo, y datos para Mifflin: sex/age/height_cm/activity_factor).',
    inputSchema: { type: 'object', properties: {} },
    handler: (env) => goalsSvc.getGoals(env),
  },

  {
    name: 'set_goals',
    description:
      'Merge de objetivos (solo las keys enviadas se actualizan). Keys: target_kcal, target_protein_g, target_carbs_g, target_fat_g, goal_weight_kg, goal_rate_kg_per_week (negativo=perder), sex (m|f), age, height_cm, activity_factor (1.2–1.9). Valores como strings.',
    inputSchema: {
      type: 'object',
      required: ['goals'],
      properties: {
        goals: { type: 'object', description: 'Mapa key→value (string), ej. {"target_kcal":"2600"}', additionalProperties: { type: 'string' } },
      },
    },
    handler: async (env, a) => {
      const parsed = validate(goalsPutSchema, { goals: a.goals });
      return { goals: await goalsSvc.putGoals(env, parsed.goals) };
    },
  },

  {
    name: 'mark_day',
    description:
      'Marca un día como logueado por completo (o no). Preguntar al usuario al final del día si logueó TODO lo comido; SOLO los días completos alimentan el TDEE adaptativo.',
    inputSchema: {
      type: 'object',
      required: ['date', 'logging_complete'],
      properties: {
        date: { type: 'string', description: 'YYYY-MM-DD' },
        logging_complete: { type: 'boolean' },
      },
    },
    handler: async (env, a) => {
      if (typeof a?.logging_complete !== 'boolean') throw unprocessable('logging_complete debe ser boolean');
      if (!a?.date) throw unprocessable('date requerido (YYYY-MM-DD)');
      await daysSvc.putDay(env, a.date, a.logging_complete);
      return { ok: true, date: a.date, logging_complete: a.logging_complete };
    },
  },

  {
    name: 'log_workout',
    description:
      'Fallback si el usuario dicta un entreno por chat en vez de la app. Mismo shape que un workout: id, ts_start, date, sets[]. El server calcula e1RM por set. Prefiere que el usuario loguee en la app cuando sea posible.',
    inputSchema: {
      type: 'object',
      required: ['workout'],
      properties: {
        workout: {
          type: 'object',
          required: ['id', 'ts_start', 'date', 'sets'],
          properties: {
            id: { type: 'string' },
            ts_start: { type: 'string', description: 'ISO-8601 con offset' },
            ts_end: { type: 'string' },
            date: { type: 'string', description: 'YYYY-MM-DD' },
            program_day_id: { type: 'string' },
            notes: { type: 'string' },
            sets: {
              type: 'array',
              items: {
                type: 'object',
                required: ['id', 'exercise_id', 'set_number', 'weight_kg', 'reps', 'rir'],
                properties: {
                  id: { type: 'string' },
                  exercise_id: { type: 'string' },
                  set_number: { type: 'number' },
                  weight_kg: { type: 'number' },
                  reps: { type: 'number' },
                  rir: { type: 'number', minimum: 0, maximum: 5 },
                  is_warmup: { type: 'boolean' },
                },
              },
            },
          },
        },
      },
    },
    handler: async (env, a) => {
      const workout = validate(workoutInputSchema, a.workout);
      return workoutsSvc.upsertWorkout(env, workout);
    },
  },
];

export const TOOLS_BY_NAME = new Map(TOOLS.map((t) => [t.name, t]));
