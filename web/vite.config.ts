import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "node:path";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
  server: {
    // In dev, proxy /api to the share-server the user starts separately via
    // `kanban channel share … --duration 1h`. SHARE_API_URL should be set to
    // e.g. http://localhost:4567 — no auth here; dev proxies through.
    proxy: process.env.SHARE_API_URL
      ? { "/api": { target: process.env.SHARE_API_URL, changeOrigin: true } }
      : undefined,
  },
  build: {
    outDir: "dist",
    sourcemap: true,
  },
  test: {
    globals: true,
    environment: "jsdom",
    setupFiles: "./vitest.setup.ts",
    css: false,
  },
});
