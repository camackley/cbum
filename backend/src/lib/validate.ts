import { z } from 'zod';
import { unprocessable } from './errors';

// Parsea con zod; en error lanza ApiError 422 con mensaje legible.
// Genérico sobre el schema para devolver el tipo de SALIDA (con defaults/transforms aplicados).
export function validate<S extends z.ZodTypeAny>(schema: S, data: unknown): z.output<S> {
  const res = schema.safeParse(data);
  if (!res.success) {
    const msg = res.error.issues
      .map((i) => {
        const path = i.path.join('.');
        return path ? `${path}: ${i.message}` : i.message;
      })
      .join('; ');
    throw unprocessable(msg);
  }
  return res.data;
}

// Parsea JSON body de forma segura (body ausente/inválido → 422).
export async function jsonBody(req: Request): Promise<unknown> {
  try {
    return await req.json();
  } catch {
    throw unprocessable('body JSON inválido o ausente');
  }
}
