import type { MiddlewareHandler } from 'hono';
import type { AppBindings } from '../types';
import { unauthorized } from './errors';

// Comparación en tiempo constante (evita timing side-channel en el token).
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// contracts §2: Authorization: Bearer ${API_TOKEN} en todo /api/*. 401 si falta/incorrecto.
export const bearerAuth: MiddlewareHandler<AppBindings> = async (c, next) => {
  const header = c.req.header('Authorization') ?? '';
  const expected = c.env.API_TOKEN;
  const prefix = 'Bearer ';
  if (!expected || !header.startsWith(prefix) || !timingSafeEqual(header.slice(prefix.length), expected)) {
    throw unauthorized();
  }
  await next();
};
