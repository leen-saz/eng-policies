# Build prompt: a new project on Leen's stack (Hoven, or any new client)

Paste everything below the line as the first message of a new conversation. Replace the `<…>` fields first.
This prompt is what we learned building Well (`leen-saz/well-ads`), so the next project starts where Well ended.

---

## 0. Who you work for and how to talk

- Owner: Leen (GitHub `leen-saz`). Reply to her in **short Saudi Arabic**, bullets, problems with exact fixes, and what was done. No guessing: every cause comes with evidence (a log line, a test, a command output).
- Code, commits, PR titles and descriptions: English. UI text addresses the user in the masculine.
- Do as much as you can yourself. Ask only for what only she can do (accounts, secrets, payments, approvals).

## 1. The project

- Name: `<project name>` (e.g. Hoven). Brand: `<colors, fonts, logo path>`. Language: Arabic first, English second.
- Repo: `leen-saz/<repo>` (Leen creates it, private and empty). Old system, if any: `<old repo / URL>`. It stays untouched and live until the cutover.
- What it does: `<one paragraph: dashboards, data sources, users>`.
- Data sources: `<Meta, Google Ads, Snap, TikTok (via MCP), Salla, GA4, …>`.

## 2. Stack (free tiers until we grow)

| Layer | Tool | Free-tier notes |
|---|---|---|
| Pages | **Astro** (TypeScript strict) on **Cloudflare Workers** | 100k requests/day, 10 ms CPU per request: keep server work small |
| API + gate | **Hono** in the same Worker under `/api/*` | |
| Navigation | Astro **ClientRouter** + `transition:persist` on the shell (sidebar + top bar) and `prefetch` on hover, **from day one** | No full page reloads between tabs |
| DB, auth, secrets vault | **Supabase** (one project per company or one project with `company_id` on every table) | Free: 500 MB DB, 2 projects per org |
| Files | **R2** private bucket per environment, served only by the Worker after the session check | 10 GB free |
| Data pipeline | **Python in GitHub Actions**, started by a **Cloudflare Cron Trigger** that calls `workflow_dispatch` | GitHub `schedule` is unreliable (it never fired on Well) |
| Public link | **Cloudflare Pages proxy** (`<name>.pages.dev`) with a service binding to the Worker; the Worker has `workers_dev: false` | No account name in the URL, no domain needed |
| AI (optional) | Workers AI binding | Free daily allowance |
| Background flows (optional) | Cloudflare Workflows | |

Rules: no React, Tailwind or other framework unless Leen approves it for this project. Visual values live in one CSS token file (colors, spacing, radius, motion: `--motion-fast: 160ms; --motion-instant: 80ms; --ease: cubic-bezier(0.16,1,0.3,1)`). One component per job (one Button, Card, Table, EmptyState). Ideas borrowed from Paperclip (MIT, `paperclipai/paperclip`): persistent layout, data cache with prefetch on hover, collapsible sidebar with counts, mobile bottom nav, one token source. Credit MIT code you copy.

## 3. Repo layout

```
src/app.ts            Hono entry: security headers → gate → /api → R2 pages → Astro; exports fetch + scheduled
src/api/routes/*.ts   one file per page group (auth, admin, account, connectors, …), dispatched by /api/<group>/:action
src/lib/              auth.ts (HMAC session cookie, Supabase REST), gate.ts, headers.ts, site.ts, cron.ts, connectors.ts
src/layouts/Shell.astro  the persistent shell (sidebar, top bar, language switch) used by every page
src/pages/<tab>/      one folder per tab; client code in src/scripts/<tab>/*.ts, not one big file
pipeline/             Python; one module per platform under pipeline/platforms/<name>.py; tests next to code
supabase/migrations/  000_…, 001_…: applied in order; CI applies them to a throwaway Postgres
proxy/                Cloudflare Pages project that forwards to the production Worker
docs/                 prd.md, plan.md, plan-progress.md, cutover.md, adr/, secrets/*.env.example (names only)
```

## 4. Phases (stop after each; keep docs/plan-progress.md current)

0. **Foundation**: PRD of the current product, phased plan, ADRs. Install `leen-saz/eng-policies` (CI, PR template, CODEOWNERS, Dependabot).
1. **Skeleton + CI**: Astro + Hono, `wrangler.jsonc` with `staging` and `production` (own R2 each), CI from the eng-policies reusable workflow pinned by SHA (Node 24, Python tests, Postgres migration check with Supabase stand-ins), staging deploys on push to main, production manual through the `production` environment.
2. **Auth**: Supabase email + password, HMAC session cookie (12 h, SameSite=Strict, `__Host-`), roles (owner / member), per-dashboard permissions re-read every 10 min, same-origin check on writes, audit log of names only.
3. **Data**: pipeline modules per platform → Supabase → `data.json` + covers to R2. Read-only on ad accounts. Vault keys (connect tab) win over GitHub secrets.
4. **Dashboards** inside the persistent shell, numbers compared to the old system for the same period (Playwright).
5. **Connect tab**: platforms, OAuth button, keys in Supabase Vault through service-role-only RPCs.
6. **Cutover** (`docs/cutover.md`): backup, stop the old writer, first run on the new one, compare numbers, switch, one-step rollback, old system kept 7 days.
7. **Tighten**: bug hunt, security review, archive the old repo.

## 5. Hard rules

- **Secrets**: never write, print, copy, log or commit a value. Leen enters them (`wrangler secret put`, `gh secret set`, Supabase dashboard). Docs list names only. Never build a tool that moves secrets between places.
- Before any write, confirm the account (`gh auth status`, `wrangler whoami`). Never create repos, Cloudflare accounts or Supabase projects yourself.
- Every change is a PR, one branch per piece. Merge only when Leen writes "ادمج"; deploy production only when she writes "انشر الإنتاج". Every PR description: what changed, why, how tested, PRD section, what Leen must do.
- Ad accounts are read-only. Writing to a platform (pause, publish, send) only behind explicit guards, owner approval, and a kill switch.
- TikTok without an API token stays on MCP (an external bot pushes a `tiktok-data` branch).
- Read the official docs (Cloudflare, Supabase, Astro, GitHub) before any setup; do not rely on memory for flags or limits.

## 6. Mistakes Well already paid for (do not repeat)

| Symptom | Root cause | Do instead |
|---|---|---|
| Login says "account not active" | The Supabase **publishable** key was saved as the service key (RLS denied `profiles`) | Service key must start with `sb_secret_`; log `keyKind()` on failure |
| Login says "wrong password" | `SUPABASE_URL` pasted with `/rest/v1` | Normalize the URL in code |
| Page styles missing on JS-drawn content | Astro scopes `<style>` | `<style is:global>` for legacy pages, or components |
| Hidden element still shows | `display:grid` beats the `hidden` attribute | `[hidden]{display:none!important}` in the base CSS |
| English mode still Arabic | Strings not in the i18n dictionary | Every user-facing string goes through `t()`; CI test renders each page in English and fails on Arabic UI text |
| Hourly data stopped | GitHub never fired `schedule` | Cloudflare Cron → `workflow_dispatch` (token with Actions: write only) |
| Vercel deploys "Blocked" | Hobby plan blocks non-owner commit authors | Deploy from outside the checkout, or avoid Vercel |
| Frames blocked | A `<meta>` CSP inside the page also applies | Keep CSP in the header only |
| "Kept tabs" in iframes | Hidden page kept keyboard shortcuts, history and language conflicts | Use the persistent Astro shell, never iframes |
| CI migration check fails | Plain Postgres has no `auth.users` / Vault | eng-policies stand-ins |
| Production deploy fails on Pages step | Astro leaves `.wrangler/deploy/config.json` | Delete it before `wrangler pages deploy` |
| New tables missing at runtime | Migrations merged but never applied | Each PR with a migration says so; apply before deploying production |

## 7. Start

1. Read this prompt, the old repo (if any) and `leen-saz/eng-policies`. Write `docs/adoption/RECON.md` (stack, risks, env var names only).
2. Ask Leen in one message for: repo created, Supabase project, Cloudflare account (`wrangler login`), and the list of people and their dashboards.
3. Then phase 0.
