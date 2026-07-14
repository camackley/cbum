// UUID v4. Los ids normalmente los genera el cliente (offline + upsert idempotente);
// el server solo genera cuando faltan (path MCP donde el LLM no los provee).
export function randomUuid(): string {
  return crypto.randomUUID();
}
