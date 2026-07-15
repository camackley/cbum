import type { Context } from 'hono';
import type { AppBindings } from '../types';
import { ApiError } from '../lib/errors';
import { timingSafeEqual } from '../lib/secure';
import { TOOLS, TOOLS_BY_NAME } from './tools';

// Versiones de protocolo MCP soportadas (para negociar en initialize).
const SUPPORTED_PROTOCOLS = new Set(['2025-06-18', '2025-03-26', '2024-11-05']);

// Servidor MCP remoto — JSON-RPC 2.0 stateless sobre Streamable HTTP (decisión en DECISIONS.md).
// Montado en POST /mcp/:secret (contracts §2). Secret incorrecto → 404 sin filtrar info.

const SERVER_INFO = { name: 'cbum-coach', version: '1.0.0' };
const DEFAULT_PROTOCOL = '2025-06-18';

interface JsonRpcRequest {
  jsonrpc: '2.0';
  id?: string | number | null;
  method: string;
  params?: any;
}

function rpcResult(id: string | number | null | undefined, result: unknown) {
  return { jsonrpc: '2.0', id: id ?? null, result };
}
function rpcError(id: string | number | null | undefined, code: number, message: string, data?: unknown) {
  return { jsonrpc: '2.0', id: id ?? null, error: { code, message, ...(data !== undefined ? { data } : {}) } };
}

async function dispatch(c: Context<AppBindings>, req: JsonRpcRequest): Promise<unknown | null> {
  const { method, id, params } = req;
  // JSON-RPC: una notificación no lleva `id` y NUNCA debe recibir respuesta.
  const isNotification = id === undefined;

  switch (method) {
    case 'initialize': {
      // Negociar: si el cliente pide una versión que soportamos, ecoarla; si no, la nuestra.
      const requested = params?.protocolVersion;
      const protocolVersion = typeof requested === 'string' && SUPPORTED_PROTOCOLS.has(requested) ? requested : DEFAULT_PROTOCOL;
      return rpcResult(id, {
        protocolVersion,
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER_INFO,
        instructions:
          'Coach de hipertrofia basado en evidencia. Nunca inventes macros: usa resolve_food antes de log_meal. Nunca uses active_kcal para recomendaciones.',
      });
    }

    // Notificaciones (sin id) → no llevan respuesta.
    case 'notifications/initialized':
    case 'notifications/cancelled':
      return null;

    case 'ping':
      return rpcResult(id, {});

    case 'tools/list':
      return rpcResult(id, {
        tools: TOOLS.map((t) => ({ name: t.name, description: t.description, inputSchema: t.inputSchema })),
      });

    case 'tools/call': {
      const name = params?.name;
      const args = params?.arguments ?? {};
      const tool = TOOLS_BY_NAME.get(name);
      if (!tool) {
        return rpcResult(id, {
          content: [{ type: 'text', text: `Tool desconocida: ${name}` }],
          isError: true,
        });
      }
      try {
        const result = await tool.handler(c.env, args);
        return rpcResult(id, {
          content: [{ type: 'text', text: JSON.stringify(result, null, 2) }],
        });
      } catch (err) {
        // Errores de dominio/validación → isError con mensaje accionable (no 500 JSON-RPC).
        const message = err instanceof ApiError ? err.message : err instanceof Error ? err.message : 'Error desconocido';
        return rpcResult(id, {
          content: [{ type: 'text', text: `Error: ${message}` }],
          isError: true,
        });
      }
    }

    default:
      // Notificación desconocida → sin respuesta. Request desconocido → error method-not-found.
      return isNotification ? null : rpcError(id, -32601, `Método no soportado: ${method}`);
  }
}

export async function handleMcp(c: Context<AppBindings>): Promise<Response> {
  // 404 si el secret no coincide — sin filtrar información.
  const secret = c.req.param('secret') ?? '';
  if (!c.env.MCP_SECRET || !timingSafeEqual(secret, c.env.MCP_SECRET)) {
    return c.json({ error: { code: 'not_found', message: 'Ruta no encontrada' } }, 404);
  }

  // GET/DELETE: no hay sesión persistente (stateless) → 405 informativo.
  if (c.req.method !== 'POST') {
    return c.json(rpcError(null, -32600, 'Usa POST con JSON-RPC 2.0'), 405);
  }

  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json(rpcError(null, -32700, 'Parse error: JSON inválido'), 400);
  }

  // Soporta batch (array) y request único.
  if (Array.isArray(body)) {
    const responses = [];
    for (const item of body) {
      const r = await dispatch(c, item as JsonRpcRequest);
      if (r !== null) responses.push(r);
    }
    return responses.length ? c.json(responses) : new Response(null, { status: 202 });
  }

  const response = await dispatch(c, body as JsonRpcRequest);
  if (response === null) return new Response(null, { status: 202 }); // notificación
  return c.json(response);
}
