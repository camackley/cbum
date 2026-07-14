# I4 — Pantallas: Nutrición, Progreso y Ajustes (Agente B)

**Prerrequisito:** I3.

## NUTRICIÓN (`Features/Nutrition/`)
- Selector de día (default hoy, swipe entre días). Totales del día vs targets arriba (mini `MacroRings`).
- Meals agrupados por `meal_group_id`, ordenados por `ts`: cada grupo con hora y `MealRow` por item.
- **Editar item** (sheet): si tiene `per_100g` → editar `quantity_g` con stepper y macros recalculados en vivo (misma regla que el server: per_100g × g/100 — el PATCH lo confirma); si no → editar macros directo con warning "entrada manual, se marca estimada". Borrar item → soft delete + quitar de HealthKit.
- Estado vacío: "Loguea con el coach 📷 — mándale fotos a Claude" + botón que abre Claude. La app NO tiene captura de comida propia (el flujo de fotos vive en Claude por diseño — costo $0 de API).
- Vista semanal: adherencia (días dentro de ±5% de kcal target), % weighed promedio, y días sin marcar completos.

## PROGRESO (`Features/Progress/`)
Fuente: `GET /api/progress` (+ por-ejercicio); fallback local con `FormulasKit`.
- **Tab Fuerza:** picker de ejercicio (buscable) → `TrendChart` de e1RM (solo válidos, contracts §5.3) con PRs marcados + lista "mejores sets" (peso×reps@RIR, fecha). Regla de honestidad: si un punto no tiene e1rm válido no se interpola — se omite.
- **Tab Volumen:** `VolumeBars` de sets efectivos por músculo de la semana en curso + selector de semanas anteriores; banda objetivo 10–20 visible.
- **Tab Cuerpo:** `TrendChart` de peso-tendencia (línea bone) con lecturas crudas como puntos tenues detrás; TDEE histórico; rate actual vs objetivo con veredicto (success/alert) — copiar shapes de `energy-status` (contracts §3.2).

## AJUSTES (`Features/Settings/`)
- **Objetivos:** form de todas las keys de goals (contracts §1) con unidades; guardar → PUT (outbox). Nota visible: "el coach puede cambiar esto por ti".
- **Conexión:** base URL del backend + API token (Keychain) + botón "probar conexión" (`GET /api/health`); estado del sync (pendientes en outbox, último cursor, errores 422 si los hay).
- **HealthKit:** estado de permisos + re-solicitar; toggles por tipo de lectura.
- **Data:** botón Exportar (`GET /api/export` → share sheet como .json); recordatorio semanal de que las fotos viven en el chat de Claude.
- **Programa:** vista read-only del programa activo (días, ejercicios, prescripciones) con nota "se edita con el coach"; mostrar `start_date` y qué día toca mañana.
- Versión de la app + link al repo.

## Pulido final (esta spec cierra el MVP)
- Accesibilidad: Dynamic Type en cuerpo (los números display pueden ser fijos), VoiceOver labels en los 12 componentes.
- App icon: negro con "CBUM" en display condensed bone.
- Revisión de rendimiento: scroll de sesión con 8 ejercicios × 5 sets sin frames caídos en un iPhone real.

## Aceptación
1. Editar porción de un meal con per_100g → macros recalculan igual local y server (comparar tras sync).
2. Progreso muestra e1RM solo de sets válidos (verificar contra un set 60×12@3 → no aparece).
3. Export produce JSON abrible con todas las tablas.
4. Cambiar target_kcal en Ajustes → Hoy refleja el nuevo anillo tras sync.
5. Checklist de integración de `00-overview.md` completa y documentada en `DECISIONS.md`.
