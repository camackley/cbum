# I3 — Pantallas: Hoy y Sesión de entreno (Agente B)

**Prerrequisito:** I1, I2. Data shapes: contracts §3.1, §3.4, §4, §5.

## Pantalla HOY (`Features/Today/`)
Fuente: `GET /api/summary/today` (refrescada por sync) + fallback a cálculo local con data SwiftData si no hay red (macros del día y targets son computables localmente; TDEE/tendencia muestran el último valor conocido con timestamp).

Layout (scroll, de arriba a abajo):
1. `CBHeader` "HOY" + fecha.
2. `MacroRings` — intake vs targets. Debajo: barra de precisión del día ("72% PESADO · 1 item con baja confianza", color estimated si <50% weighed).
3. Fila de 2 `StatCard`: **Peso tendencia** (trend_kg, delta_7d con flecha, vs `goal_rate`: success si on-track, alert si no) y **TDEE** (kcal, badge CALIBRANDO si status=calibrating).
4. Card de sesión: si `session.program_day_id != "rest"` → `ExerciseCard` compacta del día ("UPPER A — 6 ejercicios") + `CBButton` primario **EMPEZAR ENTRENO** → navega a Sesión. Si rest → "DÍA DE DESCANSO". Si `completed_today` → resumen breve de la sesión hecha.
5. Toggle "Día logueado completo" → `PUT /api/days/:date` (vía outbox). Copy: "¿Registraste todo lo que comiste hoy?" — alimenta el TDEE (contracts §5.2).

## Pantalla SESIÓN (`Features/Session/`)
Máquina de estados: `idle → active(workout en curso) → summary`. El workout activo se persiste en SwiftData desde el primer set (kill de la app no pierde nada); `ts_start` al entrar, `ts_end` al finalizar.

**Inicio:** carga `GET /api/next-session` (cachear la respuesta de la mañana para funcionar offline). Crea `Workout {program_day_id}` local.

**Vista activa:**
- Lista de ejercicios del día; el activo expandido, los demás colapsados con progreso (2/4 sets).
- Por ejercicio expandido: prescripción ("4×6–8 @ RIR 2"), sugerencia con razón ("82.5 KG — subiste: 4×8@2 la vez pasada" / "sin historial: elige peso"), y N `SetLoggerRow`:
  - Peso precargado = `suggested_weight_kg` (o el del set anterior de hoy); reps precargadas = `rep_range.max`; RIR sin preseleccionar (obliga registro consciente — precisión).
  - Guardar set → persistir local (outbox), calcular e1RM local con la MISMA fórmula de contracts §5.3 (`FormulasKit.swift` — duplicación intencional y testeada), detectar PR contra el máximo histórico local → estado PR con haptic; arrancar `RestTimer` con `rest_sec` del programa.
  - Botón "+ SET" agrega filas extra; toggle warmup por fila.
- **Sustituir ejercicio:** sheet con ejercicios del mismo `pattern` (luego mismo `muscle_group`) del catálogo local; al elegir, la prescripción se mantiene y la sugerencia de peso se recalcula del historial del nuevo ejercicio (local: última sesión con ese ejercicio + regla §5.4).
- Timer visible como barra flotante inferior al estar corriendo (no bloquea loguear otro set). Notificación local si la app está en background cuando llegue a 0.
- Salir a otra pantalla NO cancela la sesión (pill "SESIÓN EN CURSO — 00:34:12" para volver).

**Finalizar:** confirmación → `ts_end`, POST workout completo (outbox), escribir HKWorkout, → **Resumen**: duración, volumen total (Σ peso×reps sets de trabajo), sets efectivos por músculo, PRs de la sesión (celebración), y e1RMs nuevos. Botón "PREGUNTARLE AL COACH" → abre la app de Claude (URL scheme `claude://` con fallback a App Store/web).

**Entreno libre:** desde Hoy, opción secundaria "Entreno libre" → misma vista sin prescripciones, agregando ejercicios del catálogo.

## Aceptación
1. Journey completo de PLAN.md §5 pasos 3–5 en simulador, INCLUYENDO modo avión total.
2. Kill de la app con sesión activa → reabrir → sesión intacta.
3. Set que supera e1rm histórico → PR visual+haptic; verificar que el server calculó el MISMO e1rm (comparar tras sync).
4. Sustitución muestra solo ejercicios del mismo patrón.
5. Hoy refleja el toggle de día completo tras sync (`day_flags` en export).
