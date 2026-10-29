import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "tests/e2e",
  retries: process.env.CI ? 1 : 0,
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    // CI sets BASE_URL to the PR preview URL. Locally, run `npm run dev` first.
    baseURL: process.env.BASE_URL ?? "http://localhost:8787",
  },
});
