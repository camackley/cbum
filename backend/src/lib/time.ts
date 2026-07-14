// Reloj del server. Toda escritura sella updated_at con esto (epoch ms).
export function now(): number {
  return Date.now();
}

// Fecha-día actual en America/Bogota (UTC-5 fijo, sin DST). Solo para conveniencia
// de tools MCP ("qué día toca hoy") — el server no hace math de timezone en writes.
export function todayBogota(): string {
  return new Date(Date.now() - 5 * 3600 * 1000).toISOString().slice(0, 10);
}
