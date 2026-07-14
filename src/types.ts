// Bindings del Worker (D1 + secrets). Ver wrangler.jsonc y DECISIONS.md.
export interface Env {
  DB: D1Database;
  API_TOKEN: string;
  MCP_SECRET: string;
  FDC_API_KEY: string;
}

// Contexto de Hono con Env tipado.
export type AppBindings = { Bindings: Env };
