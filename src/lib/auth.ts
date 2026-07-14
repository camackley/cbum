import type { MiddlewareHandler } from 'hono';
import type { AppBindings } from '../types';
import { unauthorized } from './errors';

// contracts §2: Authorization: Bearer ${API_TOKEN} en todo /api/*. 401 si falta/incorrecto.
export const bearerAuth: MiddlewareHandler<AppBindings> = async (c, next) => {
  const header = c.req.header('Authorization') ?? '';
  const expected = c.env.API_TOKEN;
  const prefix = 'Bearer ';
  if (!expected || !header.startsWith(prefix) || header.slice(prefix.length) !== expected) {
    throw unauthorized();
  }
  await next();
};
