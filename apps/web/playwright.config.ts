import { defineConfig } from "@playwright/test";

/**
 * Playwright config — E2E landing-quality scoring rubric.
 * Runs against local dev at 4300; caller must have `pnpm dev` running.
 */
export default defineConfig({
  testDir: "./e2e",
  timeout: 90_000,
  reporter: [["list"]],
  use: {
    baseURL: "http://localhost:4300",
    trace: "on-first-retry",
    viewport: { width: 1280, height: 800 },
  },
});
