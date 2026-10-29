import { execSync } from "node:child_process";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { getPlatformProxy, type PlatformProxy } from "wrangler";
import worker, { type Env } from "../../src/index";

// Integration test against a real local D1 (Miniflare) created from the project's own migrations.
let proxy: PlatformProxy<Env>;

const call = (path: string, init?: RequestInit): Promise<Response> =>
  worker.fetch(new Request(`http://localhost${path}`, init), proxy.env);

beforeAll(async () => {
  execSync("npx wrangler d1 migrations apply DB --env staging --local", {
    stdio: "pipe",
    env: { ...process.env, CI: "true", NO_D1_WARNING: "true" },
  });
  proxy = await getPlatformProxy<Env>({ environment: "staging" });
}, 120_000);

afterAll(async () => {
  await proxy?.dispose();
});

describe("GET /health", () => {
  it("reports the environment", async () => {
    const res = await call("/health");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, environment: "staging" });
  });
});

describe("/notes", () => {
  it("creates a note and lists it", async () => {
    const created = await call("/notes", {
      method: "POST",
      body: JSON.stringify({ text: "first note" }),
    });
    expect(created.status).toBe(201);

    const list = (await (await call("/notes")).json()) as { notes: { text: string }[] };
    expect(list.notes.some((n) => n.text === "first note")).toBe(true);
  });

  it("rejects invalid input with 400 (regression: empty text used to be stored)", async () => {
    const res = await call("/notes", { method: "POST", body: JSON.stringify({ text: "   " }) });
    expect(res.status).toBe(400);
  });

  it("rejects a body that is not JSON", async () => {
    const res = await call("/notes", { method: "POST", body: "not json" });
    expect(res.status).toBe(400);
  });

  it("answers 405 for other methods and 404 for unknown paths", async () => {
    expect((await call("/notes", { method: "DELETE" })).status).toBe(405);
    expect((await call("/nope")).status).toBe(404);
  });
});
