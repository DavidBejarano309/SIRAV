import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL: process.env.SIRAV_WEB_URL || "http://localhost:5173",
    browserName: "chromium",
    channel:
      process.env.PLAYWRIGHT_CHANNEL === "chromium"
        ? undefined
        : process.env.PLAYWRIGHT_CHANNEL || "msedge",
    viewport: { width: 1440, height: 1000 },
    screenshot: "only-on-failure",
  },
  reporter: [["list"]],
  timeout: 30000,
});
