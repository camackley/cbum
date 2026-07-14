# CBUM — AI Coach personal (iOS + MCP)

Sistema de coaching estilo Built with Science usando la suscripción de Claude (sin costos de API), el Fitbit/báscula, y Apple Health como fuente de verdad.

## 0. Principios de precisión (MUST — no negociable)

Se acepta error de sensores; no se aceptan malas estimaciones. Reglas duras:

**Nutrición — jerarquía de fuentes (de más a menos precisa):**
1. **Etiqueta nutricional fotografiada + gramos pesados** → exacto. Camino preferido para todo empaquetado.
2. **Código de barras / nombre de producto** → macros desde Open Food Facts / USDA FoodData Central.
3. **Foto del plato** → Claude solo *identifica* alimentos y estima porciones; los macros se resuelven SIEMPRE contra USDA FDC vía tool `resolve_food` — **Claude nunca inventa números**.

Cada meal guarda `source` (label|barcode|photo|manual), `confidence` (0–1) y `portion_basis` (pesado|estimado). Si la confianza es < 0.7, el coach pregunta antes de loguear ("¿el arroz era ~1 taza o pesaste?"). La app marca visualmente los registros estimados vs pesados.

**Gasto calórico — TDEE adaptativo, nunca fórmulas ni el Fitbit:**
- El TDEE se calcula del balance energético real: ingesta registrada vs cambio de peso-tendencia sobre ventana móvil de 14–21 días (método MacroFactor). Requiere pesaje diario (la báscula ya lo hace) y logging honesto.
- Las "calorías quemadas" del Fitbit se guardan como dato informativo pero **jamás se usan para ajustar ingesta** (los trackers sobreestiman 20–40%).
- Primeras 2 semanas: TDEE provisional (Mifflin-St Jeor × actividad) marcado como "calibrando"; después manda la data.

**Peso — tendencia, no lecturas:** EMA (α≈0.1) sobre el peso diario. Toda decisión (ajuste de calorías, progreso) usa la tendencia; la lectura cruda nunca se muestra sola.

**Esfuerzo y progreso:**
- Esfuerzo por set = **RIR** (reps in reserve), no percepción vaga.
- Fuerza = **e1RM** (Epley: peso × (1 + reps/30)), calculado solo con sets de ≤10 reps y RIR ≤ 3 (fuera de eso la fórmula degrada — se excluyen).
- Volumen = sets efectivos (RIR ≤ 4) por grupo muscular por semana.
- Progresión sugerida por el coach basada en e1RM histórico + RIR del último set, nunca "sube 2.5kg porque sí".

## 1. Arquitectura

```
                     ┌──────────────────────────────┐
   Claude (chat) ───►│  Cloudflare Workers (gratis)  │
                     │  ├─ MCP remoto (coach)        │
   App iOS ─────────►│  ├─ REST API (bearer token)   │
                     │  └─ D1 (SQLite) ← fuente 1ª   │
                     └──────────────────────────────┘
   App iOS ◄──► Apple Health ◄── SyncFit/puente ◄── Fitbit (báscula, actividad)
```

**Dónde vive la data:** primaria en D1 (tu cuenta Cloudflare, exportable); copia en Apple Health en el iPhone. Fotos NO se almacenan — viven en el chat de Claude; a la DB solo llegan números + fuente + confianza. Google Health queda de solo-lectura de lo que el Fitbit capture por sí mismo (nada de lo logueado aparece allá — limitación de Google, no nuestra).

## 2. Esquema D1

```sql
meals(id, ts, name, kcal, protein_g, carbs_g, fat_g, fiber_g,
      source, confidence, portion_basis, fdc_id, notes)
exercises(id, name, muscle_group, pattern, equipment)   -- catálogo
workouts(id, ts_start, ts_end, program_day_id, notes)
sets(id, workout_id, exercise_id, set_number, weight_kg, reps, rir,
     is_warmup, e1rm_kg)                                 -- e1rm precalculado si aplica
body_metrics(id, ts, type, value, source)                -- weight|steps|sleep|hr_rest
weight_trend(date, ema_kg)                               -- materializada diaria
tdee_estimates(date, kcal, window_days, status)          -- adaptive|calibrating
program(id, active, json)                                -- días, ejercicios, objetivos
goals(key, value)                                        -- target_macros, goal_weight, rate
```

## 3. Tools MCP (coach)

| Tool | Uso |
|---|---|
| `resolve_food(query\|barcode)` | busca macros reales en USDA FDC / Open Food Facts |
| `log_meal(items[])` | registra tras resolver; exige source+confidence |
| `get_meals`, `get_workouts`, `get_body_metrics` | contexto por rango de fechas |
| `get_progress(exercise?)` | e1RM trends, volumen semanal por músculo, PRs |
| `get_energy_status` | TDEE adaptativo actual, tendencia de peso, adherencia |
| `get_program` / `update_program` | el coach mantiene el plan (días, ejercicios, progresiones) |
| `set_goals` / `get_goals` | macros objetivo, peso meta, ritmo (%/semana) |

## 4. App iOS — screens y mapping de datos

### 4.1 Hoy (home)
| Elemento UI | Data |
|---|---|
| Anillos: kcal + P/C/G consumidos vs objetivo | `meals` (hoy) vs `goals.target_macros` |
| Badge de precisión del día (% pesado vs estimado) | `meals.portion_basis` |
| Peso tendencia + delta semanal vs ritmo objetivo | `weight_trend`, `goals.rate` |
| TDEE actual (con estado "calibrando" si aplica) | `tdee_estimates` |
| Card "Entreno de hoy: Upper A — 6 ejercicios" → CTA Empezar | `program` (día que toca) |
| Última sync HealthKit/Fitbit | metadata local |

### 4.2 Sesión de entreno (pantalla activa)
| Elemento UI | Data |
|---|---|
| Lista de ejercicios del día con objetivo: "Press banca 4×8 @ RIR 2 — sugerido 80kg" | `program` + sugerencia de `sets` históricos (e1RM) |
| Por set: peso (precargado = última vez ± progresión), reps, RIR (selector 0–5) | escribe `sets` |
| Rest timer automático al guardar set (duración por ejercicio del programa) | `program` |
| "Sustituir ejercicio" → alternativas del mismo patrón/músculo | `exercises` (pattern) |
| Indicador en vivo: e1RM del set vs mejor histórico ("PR!" si supera) | `sets.e1rm_kg` |
| Finalizar → resumen: volumen total, sets efectivos por músculo, PRs | agregado de la sesión |

### 4.3 Nutrición
Lista de meals del día/semana con badge de fuente (⚖️ pesado / 📷 estimado / 🏷 etiqueta); editar porciones recalcula contra el mismo `fdc_id`; adherencia semanal a macros; botón "corregir con el coach" (abre Claude).

### 4.4 Progreso
Por ejercicio: gráfico e1RM en el tiempo + mejores sets. Global: volumen semanal por grupo muscular vs rangos objetivo, peso-tendencia vs meta, TDEE histórico, adherencia (días logueados completos).

### 4.5 Ajustes
Objetivos (delegables al coach), permisos HealthKit, token backend, export de toda la data (CSV/JSON desde D1), recálculo de tendencias.

**HealthKit:** la app escribe `Nutrition` y `Workout`; lee peso/pasos/sueño (que llegan del puente Fitbit) y los sube a `body_metrics`.

## 5. Journey: día de entrenamiento

1. **Mañana** — te pesas (báscula → Fitbit → puente → Apple Health). Al abrir CBUM, la app sube el peso a D1 y "Hoy" muestra tendencia actualizada y el entreno que toca.
2. **Desayuno** — empaquetado: foto de etiqueta + gramos al chat de Claude → `resolve_food` + `log_meal` (source=label). Aparece en la app en el próximo sync.
3. **Pre-gym** — abres CBUM → card "Upper A" → **Empezar**. La app ya trae pesos sugeridos calculados de tu historial.
4. **En el gym** — por serie: ajustas peso si difiere, reps, RIR → guardar (2 taps) → rest timer corre solo. Banca ocupada → "Sustituir" → eliges alternativa del mismo patrón. Ves "PR" en vivo si un set supera tu e1RM histórico.
5. **Finalizar** — resumen de sesión; la app escribe el workout a HealthKit y la data ya está en D1.
6. **Post-gym** — foto del almuerzo al chat: Claude identifica, resuelve contra USDA, pregunta si la porción no está clara (confianza < 0.7), loguea.
7. **Noche (opcional)** — le preguntas al coach "¿cómo voy?" → lee `get_energy_status` + `get_progress` y responde con TUS números: tendencia de peso vs ritmo objetivo, si toca ajustar calorías (solo si la ventana de 14 días lo justifica), y qué cambia la próxima sesión.
8. **Domingo** — el coach genera el resumen semanal y ajusta programa/macros vía `update_program`/`set_goals`, siempre explicando con qué datos.

## 6. Fases

1. **Backend + MCP** (~días): D1 + tools (incl. `resolve_food` contra USDA FDC) + deploy + conector en Claude. Resultado: coach funcional, comidas por foto con macros reales.
2. **App iOS MVP** (~1–2 sem): Hoy + Sesión de entreno + sync HealthKit. Con esto el journey completo funciona.
3. **Pulido**: Progreso, Nutrición editable, resúmenes semanales, sustitución de ejercicios.

## 7. Costos y riesgos

**$0/mes**: Cloudflare free tier, USDA FDC y Open Food Facts son gratis, suscripción Claude ya pagada, Personal Team gratis. Eventuales: $99/año Apple si vale la pena; app puente Fitbit→Health (~USD 5–10 único).

**Riesgos**: re-firma semanal (1 min con Xcode); conectores MCP custom requieren plan Pro/Max de Claude (verificar); USDA FDC cubre menos productos colombianos que gringos — Open Food Facts + entrada manual de etiquetas cubre el gap; el TDEE adaptativo es tan bueno como la constancia del logging (si un día no logueas, se marca y se excluye de la ventana).
