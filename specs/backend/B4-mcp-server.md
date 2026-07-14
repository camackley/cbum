# B4 — Servidor MCP (Agente A)

**Prerrequisito:** B2 y B3 (los tools llaman a los mismos servicios).

## Objetivo
Servidor MCP remoto en el mismo Worker, conectable como custom connector desde Claude (web/móvil/desktop), exponiendo los 13 tools de `01-contracts.md` §6.

## Implementación
- Transporte: **Streamable HTTP** en `POST /mcp/${MCP_SECRET}` (secret en URL — los custom connectors no envían headers custom; contracts §2). GET/DELETE en esa ruta: manejar según el transporte elegido.
- Opción preferida: paquete `agents` de Cloudflare (`McpAgent`) con `@modelcontextprotocol/sdk` (requiere Durable Objects; el free tier los incluye con storage SQLite). **Alternativa válida** si McpAgent complica: handler JSON-RPC stateless que implemente `initialize`, `tools/list` y `tools/call` sobre POST — suficiente para conectores de Claude. Documentar la elección en DECISIONS.md.
- Server info: name `cbum-coach`, version `1.0.0`.
- Cada tool: `inputSchema` JSON Schema completo (tipos, required, descripciones en español orientadas a que el LLM lo use bien), handler que llama al servicio correspondiente y retorna JSON legible (pretty, con unidades). Errores → `isError:true` con mensaje accionable ("falta fdc_id: resuelve primero con resolve_food").

## Descripciones de tools (guían el comportamiento del coach — escribirlas así)
- `resolve_food`: "SIEMPRE usar antes de log_meal para comida identificada por foto o nombre. Nunca estimes macros por tu cuenta."
- `log_meal`: "Registra items ya resueltos. source='photo' exige fdc_id u off_id. Si la porción no fue pesada, portion_basis='estimated' y confidence honesta (<0.7 si hay duda real de cantidad)."
- `mark_day`: "Preguntar al usuario al final del día si logueó todo; solo días completos alimentan el TDEE."
- Resto: descripción funcional breve + cuándo usarlo.

## Validaciones espejo
Los tools validan lo MISMO que la REST API (zod compartido). `update_program` verifica cada `exercise_id` contra el catálogo y responde con la lista de ids válidos si falla.

## Archivo `backend/COACH.md` (entregable extra)
Instrucciones listas para pegar en un Claude Project:
- Rol: coach de hipertrofia basado en evidencia; metodología: progresión doble, volumen por grupo muscular 10–20 sets efectivos/sem, ajuste de calorías SOLO cuando `get_energy_status` muestre ≥14 días de data y desviación sostenida del rate objetivo; explicar siempre con números del usuario.
- Flujo de fotos de comida: identificar alimentos y porciones → `resolve_food` por cada uno → confirmar porciones dudosas con el usuario → `log_meal` → responder totales del día vs targets.
- Prohibiciones: nunca inventar macros ni usar `active_kcal` para recomendaciones; nunca ajustar el programa sin mirar `get_progress`.
- Rutina dominical: resumen semanal + `update_program`/`set_goals` si aplica.

## Aceptación
- Conectado a Claude como custom connector (URL con secret): `tools/list` muestra los 13 tools.
- E2E desde chat de Claude: "loguea 150g de pechuga a la plancha" → resolve_food → log_meal → fila en `meals` con fdc_id y source correcto.
- `update_program` con exercise_id inválido → error claro, DB intacta.
- Secret incorrecto en URL → 404 sin filtrar información.
