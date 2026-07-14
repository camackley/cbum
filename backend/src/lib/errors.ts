import type { Context } from 'hono';
import type { ContentfulStatusCode } from 'hono/utils/http-status';

// Formato de error de contracts §overview: {"error":{"code","message"}}.
export class ApiError extends Error {
  code: string;
  status: ContentfulStatusCode;
  constructor(status: ContentfulStatusCode, code: string, message: string) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

export const badRequest = (code: string, msg: string) => new ApiError(400, code, msg);
export const unprocessable = (msg: string, code = 'validation_error') => new ApiError(422, code, msg);
export const notFound = (msg = 'No encontrado', code = 'not_found') => new ApiError(404, code, msg);
export const unauthorized = (msg = 'Token inválido o ausente') => new ApiError(401, 'unauthorized', msg);

// Serializa cualquier error al shape estándar.
export function errorResponse(c: Context, err: unknown) {
  if (err instanceof ApiError) {
    return c.json({ error: { code: err.code, message: err.message } }, err.status);
  }
  const message = err instanceof Error ? err.message : 'Error interno';
  return c.json({ error: { code: 'internal', message } }, 500);
}
