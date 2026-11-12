import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      "/api": "http://localhost:8080",
      "/actuator": "http://localhost:8080",
    },
  },
  test: {
    include: ["src/**/*.test.{js,jsx}"],
    environment: "jsdom",
    setupFiles: "./src/test-setup.js",
  },
});
