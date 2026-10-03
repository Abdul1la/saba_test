import path from 'node:path'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig, loadEnv } from 'vite'

export default defineConfig(({ command, mode }) => {
  // A build for the real server must name it: localhost is only the dev server's default (src/data/http.ts).
  const env = loadEnv(mode, import.meta.dirname)
  if (command === 'build' && env.VITE_USE_MOCK !== 'true' && !env.VITE_API_BASE_URL?.trim())
    throw new Error(
      'VITE_API_BASE_URL is not set. A build for the real server needs its address, e.g. ' +
        'VITE_API_BASE_URL=https://api.example.com/api/v1 npm run build (the demo, npm run build:demo, needs none).',
    )
  return {
    plugins: [react(), tailwindcss()],
    resolve: { alias: { '@': path.resolve(import.meta.dirname, './src') } },
  }
})
