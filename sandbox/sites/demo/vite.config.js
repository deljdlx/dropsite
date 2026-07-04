import { defineConfig } from 'vite'

// Vite sert les assets à une app PHP (pas son propre index.html).
// Le dev server tourne dans le conteneur Apache (port 5173) et est exposé par
// Traefik sur http://vite.localhost. Le HMR (websocket) passe par Traefik.
export default defineConfig({
  root: 'src',
  server: {
    host: '0.0.0.0',
    port: 5173,
    strictPort: true,
    cors: true,
    allowedHosts: ['vite.localhost'],
    // Origine publique des assets (vus par le navigateur).
    origin: 'http://vite.localhost',
    hmr: {
      host: 'vite.localhost',
      clientPort: 80,
      protocol: 'ws',
    },
  },
})
