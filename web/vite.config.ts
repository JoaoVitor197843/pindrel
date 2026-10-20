import { defineConfig } from 'vite'
import tailwindcss from '@tailwindcss/vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// https://vite.dev/config/
export default defineConfig({
  plugins: [tailwindcss(), svelte()],
  server: {
    // the API lives at the server root; in production the Go server serves this app and the API together
    proxy: Object.fromEntries(
      ['/auth', '/sync', '/servers', '/health', '/swagger'].map((prefix) => [prefix, 'http://localhost:8080']),
    ),
  },
})
