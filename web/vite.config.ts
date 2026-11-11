import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// The bot's web API (Sinatra, see ../web_api). It only answers requests that look like they
// were made to itself, so the dev server below rewrites the Host and Origin headers.
const BOT_API = "http://127.0.0.1:4567";

export default defineConfig({
  plugins: [react()],
  server: {
    // While coding, the page comes from Vite (port 5173) and every /api call is passed on to the bot.
    proxy: {
      "/api": { target: BOT_API, changeOrigin: true, headers: { origin: BOT_API } },
    },
  },
  test: {
    environment: "jsdom", // a pretend browser, so components can be rendered in tests
    globals: true, // describe / it / expect without importing them
    setupFiles: "./src/test/setup.ts",
  },
});
