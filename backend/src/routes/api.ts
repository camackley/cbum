import type { Hono } from 'hono';
import type { AppBindings } from '../types';
import { validate, jsonBody } from '../lib/validate';
import { badRequest } from '../lib/errors';
import {
  mealsPostSchema,
  workoutPostSchema,
  metricsPostSchema,
  exercisesPostSchema,
  dayPutSchema,
  goalsPutSchema,
  programPutSchema,
} from '../lib/schemas';
import * as mealsSvc from '../services/meals';
import * as workoutsSvc from '../services/workouts';
import * as metricsSvc from '../services/metrics';
import * as exercisesSvc from '../services/exercises';
import * as goalsSvc from '../services/goals';
import * as daysSvc from '../services/days';
import * as programSvc from '../services/program';
import { getChanges } from '../services/changes';
import { exportAll } from '../services/export';
import * as analytics from '../services/analytics';

function requireQuery(value: string | undefined, name: string): string {
  if (!value) throw badRequest('missing_param', `parámetro requerido: ${name}`);
  return value;
}

export function registerApiRoutes(api: Hono<AppBindings>): void {
  // ── Health ─────────────────────────────────────────────────────────────────
  api.get('/health', (c) => c.json({ ok: true, version: '1' }));

  // ── Meals ──────────────────────────────────────────────────────────────────
  api.post('/meals', async (c) => {
    const body = validate(mealsPostSchema, await jsonBody(c.req.raw));
    const upserted = await mealsSvc.upsertMeals(c.env, body.meals);
    return c.json({ upserted });
  });

  api.get('/meals', async (c) => {
    const from = requireQuery(c.req.query('from'), 'from');
    const to = requireQuery(c.req.query('to'), 'to');
    const meals = await mealsSvc.getMeals(c.env, from, to);
    return c.json({ meals });
  });

  api.patch('/meals/:id', async (c) => {
    const meal = await mealsSvc.patchMeal(c.env, c.req.param('id'), await jsonBody(c.req.raw));
    return c.json(meal);
  });

  api.delete('/meals/:id', async (c) => {
    await mealsSvc.deleteMeal(c.env, c.req.param('id'));
    return c.json({ ok: true });
  });

  // ── Workouts ─────────────────────────────────────────────────────────────
  api.post('/workouts', async (c) => {
    const body = validate(workoutPostSchema, await jsonBody(c.req.raw));
    const workout = await workoutsSvc.upsertWorkout(c.env, body.workout);
    return c.json(workout);
  });

  api.get('/workouts', async (c) => {
    const workouts = await workoutsSvc.getWorkouts(c.env, {
      from: c.req.query('from'),
      to: c.req.query('to'),
      exercise_id: c.req.query('exercise_id'),
    });
    return c.json({ workouts });
  });

  api.delete('/workouts/:id', async (c) => {
    await workoutsSvc.deleteWorkout(c.env, c.req.param('id'));
    return c.json({ ok: true });
  });

  // ── Exercises ────────────────────────────────────────────────────────────
  api.get('/exercises', async (c) => {
    const exercises = await exercisesSvc.getExercises(c.env);
    return c.json({ exercises });
  });

  api.post('/exercises', async (c) => {
    const body = validate(exercisesPostSchema, await jsonBody(c.req.raw));
    const upserted = await exercisesSvc.upsertExercises(c.env, body.exercises);
    return c.json({ upserted });
  });

  // ── Body metrics ───────────────────────────────────────────────────────────
  api.post('/body-metrics', async (c) => {
    const body = validate(metricsPostSchema, await jsonBody(c.req.raw));
    const upserted = await metricsSvc.upsertBodyMetrics(c.env, body.metrics);
    return c.json({ upserted });
  });

  api.get('/body-metrics', async (c) => {
    const metrics = await metricsSvc.getBodyMetrics(c.env, {
      type: c.req.query('type'),
      from: c.req.query('from'),
      to: c.req.query('to'),
    });
    return c.json({ metrics });
  });

  // ── Days ───────────────────────────────────────────────────────────────────
  api.put('/days/:date', async (c) => {
    const body = validate(dayPutSchema, await jsonBody(c.req.raw));
    await daysSvc.putDay(c.env, c.req.param('date'), body.logging_complete);
    return c.json({ ok: true });
  });

  // ── Goals ──────────────────────────────────────────────────────────────────
  api.get('/goals', async (c) => c.json({ goals: await goalsSvc.getGoals(c.env) }));

  api.put('/goals', async (c) => {
    const body = validate(goalsPutSchema, await jsonBody(c.req.raw));
    const goals = await goalsSvc.putGoals(c.env, body.goals);
    return c.json({ goals });
  });

  // ── Program ────────────────────────────────────────────────────────────────
  api.get('/program', async (c) => {
    const program = await programSvc.getActiveProgram(c.env);
    if (!program) return c.json({ program: null });
    return c.json({ program: { id: program.id, start_date: program.start_date, json: program.json } });
  });

  api.put('/program', async (c) => {
    const program = await programSvc.putProgram(c.env, await jsonBody(c.req.raw));
    return c.json({ program: { id: program.id, start_date: program.start_date, json: program.json } });
  });

  // ── Analytics (stubs B2 → B3) ────────────────────────────────────────────
  api.get('/summary/today', async (c) => {
    const date = requireQuery(c.req.query('date'), 'date');
    return c.json(await analytics.summaryToday(c.env, date));
  });

  api.get('/energy-status', async (c) => c.json(await analytics.energyStatus(c.env)));

  api.get('/progress', async (c) => c.json(await analytics.progress(c.env, c.req.query('exercise_id'))));

  api.get('/next-session', async (c) => {
    const date = requireQuery(c.req.query('date'), 'date');
    return c.json(await analytics.nextSession(c.env, date));
  });

  // ── Sync + export ────────────────────────────────────────────────────────
  api.get('/changes', async (c) => {
    const sinceRaw = c.req.query('since') ?? '0';
    const since = Number(sinceRaw);
    if (!Number.isFinite(since) || since < 0) throw badRequest('bad_cursor', 'since debe ser epoch_ms >= 0');
    return c.json(await getChanges(c.env, since));
  });

  api.get('/export', async (c) => c.json(await exportAll(c.env)));
}
