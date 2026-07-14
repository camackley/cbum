# I2 — Capa de datos, sync offline y HealthKit (Agente B)

**Prerrequisito:** I1. Shapes y reglas: `01-contracts.md` §1, §3, §7.

## Modelos (SwiftData)
`@Model` espejo de las tablas: `Meal`, `Exercise`, `Workout`, `WorkoutSet`, `BodyMetric`, `DayFlag`, `ProgramModel`, `Goal`. Campos idénticos a contracts §1 (ids String uuid, fechas String como el server las maneja + helpers a `Date`). Enums Swift para `source`, `portion_basis`, `muscle_group`, `pattern` con rawValues EXACTOS a los CHECK de SQL.

Además `Outbox` (@Model): `{id, createdAt, endpoint, method, bodyJSON, attempts}`.

## API client (`Services/APIClient.swift`)
- `URLSession` async/await; base URL y token en `AppConfig` (leídos de Ajustes/Keychain — el token NUNCA hardcodeado).
- Structs Codable request/response 1:1 con contracts §3 (incluye `SummaryToday`, `EnergyStatus`, `Progress`, `NextSession`).
- Errores tipados: `unauthorized`, `validation(message)`, `network`, `server`.

## Sync engine (`Services/SyncEngine.swift`) — offline-first, el gym tiene mal internet
**Escritura:** todo write del usuario se guarda PRIMERO en SwiftData (UI instantánea) y encola en `Outbox`. Un worker drena el outbox en orden (FIFO): éxito → eliminar entrada; fallo de red → reintentar con backoff (2s, 8s, 30s, luego al próximo trigger); 422 → NO reintentar, marcar el registro local con `syncError` y mostrarlo en Ajustes (no puede pasar si la app valida igual que el server).
**Lectura:** pull incremental `GET /api/changes?since=cursor` (cursor persistido en UserDefaults; 0 la primera vez). Aplicar upserts por id; `deleted=1` → borrar local. El server SIEMPRE gana en conflicto (la app no edita registros viejos offline salvo meals propios recién creados).
**Triggers de sync:** app pasa a foreground, después de cada write local, pull-to-refresh, y al terminar un entreno.
**Punto crítico:** los ids se generan en el cliente (UUID v4) y los POST del server son upserts — reintentos jamás duplican.

## HealthKit (`Services/HealthKitService.swift`) — mapeo exacto en contracts §7
**Solicitud de permisos** al primer arranque (Ajustes permite re-pedir): write nutrición+workout; read bodyMass, stepCount, sleepAnalysis, activeEnergyBurned.
**Escritura (después del éxito del save local, no del sync):**
- Meal → `HKCorrelation` tipo food con samples: dietaryEnergyConsumed (kcal), dietaryProtein, dietaryCarbohydrates, dietaryFatTotal, dietaryFiber (g), fecha = `ts`, metadata `["cbum_id": meal.id]` (evita duplicar si se re-escribe).
- Workout terminado → `HKWorkout` `.traditionalStrengthTraining` con ts_start/ts_end y metadata `["cbum_id": workout.id]`.
- Meal/workout borrado o editado → borrar el sample HK por metadata cbum_id y re-escribir.
**Lectura (HK → API):** `HKAnchoredObjectQuery` por tipo con anchor persistido:
- bodyMass → cada sample como `body_metrics {type:"weight_kg", ts, value}` (source `healthkit`).
- stepCount y activeEnergyBurned → total por día (statistics collection query, 1 valor/día, ts = fin de día Bogotá).
- sleepAnalysis → horas dormidas por noche (sumar samples `asleep*` entre 18:00 y 18:00 sig., asignadas a la fecha de despertar).
Enviar via `POST /api/body-metrics` (por el outbox como todo write). El unique del server deduplica re-syncs.

## Aceptación
1. Modo avión: loguear meal manual y un workout → UI refleja todo; al reconectar, outbox drena y `GET /api/export` los muestra.
2. Kill de la app a mitad de outbox → al reabrir, drena sin duplicar (verificar counts en server).
3. Peso agregado manualmente en app Salud (simulador) → aparece en `body_metrics` tras foreground.
4. Meal logueado → visible en app Salud (Nutrición); borrarlo en CBUM → desaparece de Salud.
