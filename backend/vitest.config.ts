import { defineConfig } from 'vitest/config';

// Las fórmulas son funciones puras (sin D1) → runner node estándar.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts'],
  },
});
