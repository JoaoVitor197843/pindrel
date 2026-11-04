import { defineConfig } from 'vitest/config'
import tailwindcss from '@tailwindcss/vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { svelteTesting } from '@testing-library/svelte/vite'
import { inlineCssAndPrecompress } from './vite.assets.ts'

// https://vite.dev/config/
export default defineConfig({
  plugins: [tailwindcss(), svelte(), svelteTesting(), inlineCssAndPrecompress()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
  },
  server: {
    // the API lives at the server root; in production the Go server serves this app and the API together
    proxy: Object.fromEntries(
      ['/auth', '/sync', '/server', '/health', '/swagger'].map((prefix) => [prefix, 'http://localhost:8080']),
    ),
  },
})
