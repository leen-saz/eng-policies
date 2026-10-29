import { validateNote } from "./validate";

export interface Env {
  DB: D1Database;
  BUCKET: R2Bucket;
  ENVIRONMENT: string;
}

const json = (data: unknown, status = 200): Response =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true, environment: env.ENVIRONMENT });
    }

    if (request.method === "GET" && url.pathname === "/") {
      return new Response("<h1>eng-policies sample app</h1>", {
        headers: { "content-type": "text/html; charset=utf-8" },
      });
    }

    if (url.pathname === "/notes") {
      if (request.method === "GET") {
        const { results } = await env.DB.prepare(
          "SELECT id, text, created_at FROM notes ORDER BY id DESC LIMIT 50",
        ).all();
        return json({ notes: results });
      }

      if (request.method === "POST") {
        let body: unknown;
        try {
          body = await request.json();
        } catch {
          return json({ error: "body must be valid JSON" }, 400);
        }
        const parsed = validateNote(body);
        if (!parsed.ok) {
          return json({ error: parsed.error }, 400);
        }
        const row = await env.DB.prepare("INSERT INTO notes (text) VALUES (?) RETURNING id, text, created_at")
          .bind(parsed.value.text)
          .first();
        return json({ note: row }, 201);
      }

      return json({ error: "method not allowed" }, 405);
    }

    return json({ error: "not found" }, 404);
  },
} satisfies ExportedHandler<Env>;
