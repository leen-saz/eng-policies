import { execSync } from "node:child_process";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { getPlatformProxy, type PlatformProxy } from "wrangler";

// Integration tests run against a real local D1 (Miniflare) built from migrations/.
let proxy: PlatformProxy<{ DB: D1Database }>;

beforeAll(async () => {
  execSync("npx wrangler d1 migrations apply DB --env staging --local", {
    stdio: "pipe",
    env: { ...process.env, CI: "true", NO_D1_WARNING: "true" },
  });
  proxy = await getPlatformProxy<{ DB: D1Database }>({ environment: "staging" });
}, 120_000);

afterAll(async () => {
  await proxy?.dispose();
});

describe("baseline schema", () => {
  it("has the app_meta table", async () => {
    const row = await proxy.env.DB.prepare("SELECT value FROM app_meta WHERE key = 'schema'").first<{ value: string }>();
    expect(row?.value).toBe("baseline");
  });
});
