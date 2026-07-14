// Helpers finos sobre env.DB.prepare(). Sin ORM (decisión documentada en DECISIONS.md).

// Construye un UPSERT idempotente por columna(s) de conflicto.
// columns: nombres en orden; values: valores en el MISMO orden.
export function buildUpsert(
  table: string,
  columns: string[],
  conflictTarget: string, // ej. 'id' o '(type, ts, source)'
): string {
  const placeholders = columns.map(() => '?').join(', ');
  const updates = columns
    .filter((col) => col !== 'id')
    .map((col) => `${col} = excluded.${col}`)
    .join(', ');
  return `INSERT INTO ${table} (${columns.join(', ')}) VALUES (${placeholders}) ON CONFLICT${conflictTarget.startsWith('(') ? conflictTarget : `(${conflictTarget})`} DO UPDATE SET ${updates}`;
}

// Parseo seguro de JSON de columnas TEXT.
export function parseJson<T>(raw: string | null | undefined, fallback: T): T {
  if (raw == null) return fallback;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}
