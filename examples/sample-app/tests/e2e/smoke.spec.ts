import { expect, test } from "@playwright/test";

// Runs against BASE_URL (the PR preview in CI, `wrangler dev` locally).
test("health endpoint answers", async ({ request }) => {
  const res = await request.get("/health");
  expect(res.ok()).toBe(true);
  expect(await res.json()).toMatchObject({ ok: true });
});

test("home page renders", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("h1")).toContainText("eng-policies sample app");
});
