-- Cache de resoluciones de alimentos (B3). TTL 30 días se controla en app (updated_at).
-- key = 'fdc:{id}' | 'off:{barcode}' | 'q:{hash}'.
CREATE TABLE food_cache (
  key TEXT PRIMARY KEY,
  json TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
