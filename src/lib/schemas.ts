import { z } from 'zod';

// ── Primitivos ────────────────────────────────────────────────────────────────
export const zDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'fecha debe ser YYYY-MM-DD');

// ISO-8601 con offset (o Z). Ej: 2026-07-14T18:30:00-05:00
export const zTs = z
  .string()
  .regex(
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?([+-]\d{2}:\d{2}|Z)$/,
    'timestamp debe ser ISO-8601 con offset',
  );

export const zUuid = z.string().min(1, 'id requerido');

export const MUSCLE_GROUPS = ['chest', 'back', 'shoulders', 'biceps', 'triceps', 'quads', 'hamstrings', 'glutes', 'calves', 'abs'] as const;
export const PATTERNS = ['horizontal_push', 'vertical_push', 'horizontal_pull', 'vertical_pull', 'squat', 'hinge', 'lunge', 'isolation', 'carry', 'core'] as const;
export const EQUIPMENT = ['barbell', 'dumbbell', 'machine', 'cable', 'bodyweight', 'smith'] as const;
export const MEAL_SOURCES = ['label', 'barcode', 'photo', 'manual'] as const;
export const PORTION_BASES = ['weighed', 'estimated'] as const;
export const METRIC_TYPES = ['weight_kg', 'steps', 'sleep_hours', 'resting_hr', 'active_kcal'] as const;

// bool o 0/1 → boolean
const zBoolish = z.union([z.boolean(), z.literal(0), z.literal(1)]).transform((v) => v === true || v === 1);

// ── Per-100g ──────────────────────────────────────────────────────────────────
export const per100gSchema = z.object({
  kcal: z.number(),
  protein_g: z.number(),
  carbs_g: z.number(),
  fat_g: z.number(),
  fiber_g: z.number().nullish(),
});
export type Per100g = z.infer<typeof per100gSchema>;

// ── Meals ─────────────────────────────────────────────────────────────────────
export const mealInputSchema = z
  .object({
    id: zUuid.optional(), // MCP puede generarlo; REST lo exige (se valida abajo)
    ts: zTs,
    date: zDate,
    meal_group_id: zUuid.optional(),
    name: z.string().min(1),
    quantity_g: z.number().positive().nullish(),
    kcal: z.number().min(0),
    protein_g: z.number().min(0),
    carbs_g: z.number().min(0),
    fat_g: z.number().min(0),
    fiber_g: z.number().min(0).nullish(),
    per_100g: per100gSchema.nullish(),
    source: z.enum(MEAL_SOURCES),
    confidence: z.number().min(0, 'confidence debe estar en [0,1]').max(1, 'confidence debe estar en [0,1]'),
    portion_basis: z.enum(PORTION_BASES),
    fdc_id: z.number().int().nullish(),
    off_id: z.string().nullish(),
    notes: z.string().nullish(),
  })
  .superRefine((m, ctx) => {
    // REGLA (precisión): source='photo' ⇒ fdc_id u off_id OBLIGATORIO.
    if (m.source === 'photo' && m.fdc_id == null && (m.off_id == null || m.off_id === '')) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "source='photo' exige fdc_id u off_id (resuelve primero con resolve_food)",
        path: ['fdc_id'],
      });
    }
  });
export type MealInput = z.infer<typeof mealInputSchema>;

export const mealsPostSchema = z.object({ meals: z.array(mealInputSchema).min(1) });

export const mealPatchSchema = z
  .object({
    quantity_g: z.number().positive().nullish(),
    name: z.string().min(1).optional(),
    kcal: z.number().min(0).optional(),
    protein_g: z.number().min(0).optional(),
    carbs_g: z.number().min(0).optional(),
    fat_g: z.number().min(0).optional(),
    fiber_g: z.number().min(0).nullish(),
    portion_basis: z.enum(PORTION_BASES).optional(),
    confidence: z.number().min(0).max(1).optional(),
    notes: z.string().nullish(),
  })
  .refine((o) => Object.keys(o).length > 0, 'patch vacío');

// ── Exercises ─────────────────────────────────────────────────────────────────
export const exerciseInputSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  muscle_group: z.enum(MUSCLE_GROUPS),
  pattern: z.enum(PATTERNS),
  equipment: z.enum(EQUIPMENT),
  increment_kg: z.number().positive(),
});
export type ExerciseInput = z.infer<typeof exerciseInputSchema>;
export const exercisesPostSchema = z.object({ exercises: z.array(exerciseInputSchema).min(1) });

// ── Sets / Workouts ───────────────────────────────────────────────────────────
export const setInputSchema = z.object({
  id: zUuid,
  exercise_id: z.string().min(1),
  set_number: z.number().int().min(1),
  weight_kg: z.number().min(0),
  reps: z.number().int().min(0),
  rir: z.number().int().min(0, 'rir debe estar entre 0 y 5').max(5, 'rir debe estar entre 0 y 5'),
  is_warmup: zBoolish.default(false),
});
export type SetInput = z.infer<typeof setInputSchema>;

export const workoutInputSchema = z.object({
  id: zUuid,
  ts_start: zTs,
  ts_end: zTs.nullish(),
  date: zDate,
  program_day_id: z.string().nullish(),
  notes: z.string().nullish(),
  sets: z.array(setInputSchema).default([]),
});
export type WorkoutInput = z.infer<typeof workoutInputSchema>;
export const workoutPostSchema = z.object({ workout: workoutInputSchema });

// ── Body metrics ──────────────────────────────────────────────────────────────
export const metricInputSchema = z.object({
  id: zUuid,
  ts: zTs,
  date: zDate,
  type: z.enum(METRIC_TYPES),
  value: z.number(),
  source: z.string().min(1),
});
export type MetricInput = z.infer<typeof metricInputSchema>;
export const metricsPostSchema = z.object({ metrics: z.array(metricInputSchema).min(1) });

// ── Day flags / Goals ─────────────────────────────────────────────────────────
export const dayPutSchema = z.object({ logging_complete: z.boolean() });
export const goalsPutSchema = z.object({ goals: z.record(z.string(), z.string()) });

// ── Program (§4) ──────────────────────────────────────────────────────────────
export const programExerciseSchema = z.object({
  exercise_id: z.string().min(1),
  sets: z.number().int().min(1),
  rep_range: z
    .tuple([z.number().int().min(1), z.number().int().min(1)])
    .refine(([min, max]) => min <= max, 'rep_range debe ser [min,max] con min ≤ max'),
  target_rir: z.number().int().min(0).max(5),
  rest_sec: z.number().int().min(0),
  notes: z.string().nullish(),
});
export const programDaySchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  exercises: z.array(programExerciseSchema).min(1),
});
export const programJsonSchema = z.object({
  version: z.number().int(),
  name: z.string().min(1),
  days: z.array(programDaySchema).min(1),
  schedule: z.array(z.string().min(1)).min(1),
});
export type ProgramJson = z.infer<typeof programJsonSchema>;
export const programPutSchema = z.object({
  start_date: zDate,
  json: programJsonSchema,
});
