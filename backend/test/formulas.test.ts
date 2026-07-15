import { describe, it, expect } from 'vitest';
import {
  emaSeries,
  adaptiveTdee,
  mifflinTdee,
  computeE1rm,
  suggestWeight,
  detectPr,
  weeklyEffectiveSets,
  type MifflinInput,
} from '../src/lib/formulas';

// Todos los test vectors de contracts §5 (obligatorios).

describe('§5.1 EMA de peso', () => {
  it('[80.0, 81.0, gap, 80.5] → [80.0, 80.1, 80.1, 80.14]', () => {
    const series = emaSeries([
      { date: '2026-01-01', kg: 80.0 },
      { date: '2026-01-02', kg: 81.0 },
      // 2026-01-03 sin pesaje (carry-forward)
      { date: '2026-01-04', kg: 80.5 },
    ]);
    expect(series.map((p) => p.date)).toEqual(['2026-01-01', '2026-01-02', '2026-01-03', '2026-01-04']);
    expect(series[0]!.ema).toBeCloseTo(80.0, 2);
    expect(series[1]!.ema).toBeCloseTo(80.1, 2);
    expect(series[2]!.ema).toBeCloseTo(80.1, 2); // carry-forward
    expect(series[3]!.ema).toBeCloseTo(80.14, 2);
  });

  it('promedia múltiples pesajes del mismo día', () => {
    const series = emaSeries([
      { date: '2026-01-01', kg: 79.0 },
      { date: '2026-01-01', kg: 81.0 }, // promedio 80.0
    ]);
    expect(series[0]!.ema).toBeCloseTo(80.0, 2);
  });
});

describe('§5.2 TDEE adaptativo', () => {
  const mifflin: MifflinInput = { sex: 'm', age: 30, heightCm: 175, activityFactor: 1.55, weightKg: 82.4 };

  it('intake 2500, ΔEMA −0.6kg/21d → 2720 (adaptive)', () => {
    const res = adaptiveTdee({
      windowDays: 21,
      completeDayKcals: Array(16).fill(2500), // ≥10 días complete
      weighinsCount: 19, // ≥10 pesajes
      emaFirst: 83.0,
      emaLast: 82.4, // ΔEMA = −0.6
      trendCoversWindow: true,
      mifflin,
    });
    expect(res.status).toBe('adaptive');
    expect(res.kcal).toBeCloseTo(2720, 1);
  });

  it('9 días complete → calibrating con Mifflin', () => {
    const res = adaptiveTdee({
      windowDays: 21,
      completeDayKcals: Array(9).fill(2500), // <10 → calibrating
      weighinsCount: 19,
      emaFirst: 83.0,
      emaLast: 82.4,
      trendCoversWindow: true,
      mifflin,
    });
    expect(res.status).toBe('calibrating');
    expect(res.kcal).toBeCloseTo(2747.8, 1);
  });

  it('Mifflin directo: m,30,175,82.4,1.55 → 2747.8', () => {
    expect(mifflinTdee({ sex: 'm', age: 30, heightCm: 175, activityFactor: 1.55, weightKg: 82.4 })).toBeCloseTo(2747.8, 1);
  });

  it('<10 pesajes también → calibrating', () => {
    const res = adaptiveTdee({
      windowDays: 21,
      completeDayKcals: Array(16).fill(2500),
      weighinsCount: 9, // <10 pesajes
      emaFirst: 83.0,
      emaLast: 82.4,
      trendCoversWindow: true,
      mifflin,
    });
    expect(res.status).toBe('calibrating');
  });

  it('trend NO cubre la ventana (onboarding) → calibrating, NO TDEE corrupto', () => {
    // Regresión del bug emaFirst=0: aunque haya ≥10 complete y ≥10 pesajes, si el
    // trend no cubre la ventana no se computa ΔEMA → Mifflin, nunca un balance absurdo.
    const res = adaptiveTdee({
      windowDays: 21,
      completeDayKcals: Array(16).fill(2500),
      weighinsCount: 19,
      emaFirst: 0, // valor centinela que ANTES corrompía el cálculo
      emaLast: 82.4,
      trendCoversWindow: false,
      mifflin,
    });
    expect(res.status).toBe('calibrating');
    expect(res.kcal).toBeCloseTo(2747.8, 1); // Mifflin, no un número negativo/absurdo
  });
});

describe('§5.3 e1RM', () => {
  it('100kg × 8 @ RIR 2 → 133.3', () => {
    expect(computeE1rm(100, 8, 2, false)).toBeCloseTo(133.3, 1);
  });
  it('60kg × 12 @ RIR 3 (15 > 12) → null', () => {
    expect(computeE1rm(60, 12, 3, false)).toBeNull();
  });
  it('warmup → null', () => {
    expect(computeE1rm(100, 8, 2, true)).toBeNull();
  });
  it('límite reps+rir = 12 → válido', () => {
    expect(computeE1rm(100, 10, 2, false)).not.toBeNull();
  });
});

describe('§5.4 Sugerencia de peso (doble progresión)', () => {
  const presc = { repRange: [6, 8] as [number, number], targetRir: 2, sets: 4 };

  it('4×80×8@2 → 82.5 (increase)', () => {
    const sets = [1, 2, 3, 4].map((n) => ({ set_number: n, weight_kg: 80, reps: 8, rir: 2 }));
    const res = suggestWeight(presc, sets, 2.5);
    expect(res.suggested_weight_kg).toBeCloseTo(82.5, 2);
    expect(res.suggestion_reason).toBe('double_progression_increase');
  });

  it('un set 80×7@2 → 80 (repeat)', () => {
    const sets = [
      { set_number: 1, weight_kg: 80, reps: 8, rir: 2 },
      { set_number: 2, weight_kg: 80, reps: 7, rir: 2 }, // no llega a max
      { set_number: 3, weight_kg: 80, reps: 8, rir: 2 },
      { set_number: 4, weight_kg: 80, reps: 8, rir: 2 },
    ];
    const res = suggestWeight(presc, sets, 2.5);
    expect(res.suggested_weight_kg).toBeCloseTo(80, 2);
    expect(res.suggestion_reason).toBe('repeat_weight');
  });

  it('menos sets de los prescritos (2 de 4, ambos al tope) → repeat, NO increase', () => {
    const sets = [
      { set_number: 1, weight_kg: 80, reps: 8, rir: 2 },
      { set_number: 2, weight_kg: 80, reps: 8, rir: 2 },
    ];
    const res = suggestWeight(presc, sets, 2.5); // presc.sets = 4
    expect(res.suggested_weight_kg).toBeCloseTo(80, 2);
    expect(res.suggestion_reason).toBe('repeat_weight');
  });

  it('sin historia → null', () => {
    const res = suggestWeight(presc, [], 2.5);
    expect(res.suggested_weight_kg).toBeNull();
    expect(res.suggestion_reason).toBe('no_history');
  });

  it('último_peso = peso del último set de trabajo', () => {
    const sets = [
      { set_number: 1, weight_kg: 82.5, reps: 8, rir: 2 },
      { set_number: 2, weight_kg: 80, reps: 8, rir: 2 }, // último → base 80
    ];
    // prescritos 2, se cumplen los 2 → increase sobre el último peso (80).
    const res = suggestWeight({ repRange: [6, 8], targetRir: 2, sets: 2 }, sets, 2.5);
    expect(res.suggested_weight_kg).toBeCloseTo(82.5, 2); // 80 + 2.5
  });
});

describe('§5.5 PR y sets efectivos', () => {
  it('e1rm 133.3 vs máx previo 130 → true', () => {
    expect(detectPr(133.3, [120, 130, 125])).toBe(true);
  });
  it('e1rm 133.3 vs 133.3 → false', () => {
    expect(detectPr(133.3, [133.3])).toBe(false);
  });
  it('e1rm null → false', () => {
    expect(detectPr(null, [100])).toBe(false);
  });
  it('sin historia previa → true (primer PR)', () => {
    expect(detectPr(100, [])).toBe(true);
  });

  it('sets efectivos: rir ≤ 4 y no warmup, por semana ISO y músculo', () => {
    const rows = weeklyEffectiveSets([
      { date: '2026-07-14', muscle_group: 'chest', is_warmup: false, rir: 2 }, // efectivo
      { date: '2026-07-14', muscle_group: 'chest', is_warmup: false, rir: 4 }, // efectivo (rir=4)
      { date: '2026-07-14', muscle_group: 'chest', is_warmup: false, rir: 5 }, // NO (rir>4)
      { date: '2026-07-14', muscle_group: 'chest', is_warmup: true, rir: 1 }, // NO (warmup)
    ]);
    expect(rows).toHaveLength(1);
    expect(rows[0]!.muscle_group).toBe('chest');
    expect(rows[0]!.effective_sets).toBe(2);
    expect(rows[0]!.week).toMatch(/^2026-W\d{2}$/);
  });
});
