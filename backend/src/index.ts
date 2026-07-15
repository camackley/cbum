import { Hono } from 'hono';
import type { AppBindings } from './types';
import { bearerAuth } from './lib/auth';
import { errorResponse } from './lib/errors';
import { registerApiRoutes } from './routes/api';
import { handleMcp } from './mcp/server';

const app = new Hono<AppBindings>();

// Health público (sin auth) — útil para monitoreo. También hay /api/health con auth.
app.get('/health', (c) => c.json({ ok: true, version: '1' }));

// MCP: POST /mcp/:secret (contracts §2). El secret va en la URL (los custom connectors
// de Claude no mandan headers custom). 404 si no coincide → no filtra información.
app.all('/mcp/:secret', (c) => handleMcp(c));

// REST API — todo /api/* exige Bearer token.
const api = new Hono<AppBindings>();
api.use('*', bearerAuth);
registerApiRoutes(api);
app.route('/api', api);

// Manejo de errores uniforme.
app.onError((err, c) => errorResponse(c, err));
app.notFound((c) => c.json({ error: { code: 'not_found', message: 'Ruta no encontrada' } }, 404));

export default app;
