import { expect, test } from "@playwright/test";

// Runs against BASE_URL (the PR preview in CI, `wrangler dev` locally).
test("the app answers", async ({ page }) => {
  const res = await page.goto("/");
  expect(res?.status()).toBeLessThan(500);
});
