---
name: adopt-existing
description: Adopt eng-policies on an EXISTING live project (brownfield) in modules M0 to M10, one branch and PR per module, including the move from Vercel to Cloudflare. Use when the user says "adopt eng-policies on this project", "bring this project up to standard", or "move this app from Vercel to Cloudflare".
---

# Adopt eng-policies on an existing project (modular)

The system is live. Do not rewrite working code, do not change behaviour, do not touch production unless a module says so and the owner approves.

## How to run
- Work through the modules in order. Each module is one branch `adopt/mN-<name>` and one PR.
- At the start of each module, say in two lines what it will change. At the end show: files changed, tests run with results, CI status, and anything the owner must do by hand.
- Stop after each module and wait for approval before merging and moving on.
- Track state in `docs/adoption/PROGRESS.md` (module, status, PR link, notes) so any session can resume.
- If a module is blocked or too big, mark it `deferred` with the reason and continue with the next independent one. Modules marked (needs X) depend on earlier ones; the rest can run in any order after M2.
- Never print, commit or ask the owner to paste secret values. Give the exact command for the owner to run.
- Check the current official docs (Cloudflare, GitHub, OpenNext) before writing any config. Do not rely on memory for flags or limits.

## Accounts (check before every module)
- GitHub: the repo lives on the owner's GitHub account registered with the wellunion email.
- Cloudflare: the target account is the one registered with the brands email.
- Vercel: the app is live there and stays live until cutover.
- The owner logs in herself (`gh auth login`, `wrangler login`, `vercel login`). Before any command that writes, run `gh auth status` and `wrangler whoami` and show which account is active. If it is the wrong one, stop.
- GitHub reaches Cloudflare through GitHub Actions plus a scoped Cloudflare API token (Workers, D1, R2 edit on that account only), stored as GitHub secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` which the owner creates and sets herself. Do not use the Cloudflare dashboard Git integration: deploys go through the CI gates.

## Run order
M0, M1, M2, M3, M9 (move off Vercel), M4, M5, M6, M7, M8, M10.
The safety-net tests (M3) come before the move so they can prove the Cloudflare version behaves exactly like the Vercel one.

## Modules

### M0: Recon and snapshot (read-only)
Inventory the stack, entry points, deploy method, database, external services, env vars (names only), and test coverage. Confirm the app builds and runs locally. Ask the owner to take a DB backup and confirm it. Output `docs/adoption/RECON.md` with a risk list ranked high to low. No code changes.

### M1: Repo hygiene (needs M0)
Put the project on GitHub if it is not. Add `.gitignore`, `.dev.vars.example`, PR template, CODEOWNERS. Scan the full git history for committed secrets and list each one (name and file, never the value) so the owner can rotate it.

### M2: Document the core (needs M0)
Run BMAD's brownfield `document-project` flow. Produce `docs/architecture.md` (how it works today), `docs/prd.md` (what it does today) and the project `CLAUDE.md` from the template. This becomes the core that must not be left. The owner reviews and approves it before anything else changes.

### M3: Safety-net tests (needs M2)
Write characterization tests that pin current behaviour of the most critical flows from RECON's risk list (start with the top 5). Tests must pass against unchanged code. No refactoring.

### M4: CI, gradual (needs M3)
Install the caller workflows from eng-policies (`install.sh . --mode existing`). Build and tests are required; lint and typecheck run warn-only. Record the warning count as the baseline in PROGRESS.md.

### M5: Security
Move secrets out of code into GitHub Secrets and Cloudflare secrets (the owner runs the set commands). Enable Dependabot and CodeQL. Report vulnerable dependencies; upgrade only patch versions here, larger upgrades become separate stories.

### M6: Database baseline (needs M3)
Capture the current schema as `migrations/0000_baseline.sql` without altering the live DB. Add an index review: list slow or unindexed queries as stories, do not apply them yet.

### M7: Environments and gates (needs M4)
Create staging (own D1 and R2) and the production environment gate with the owner as required reviewer. Apply the `main` ruleset (PR and CI required, no force-push) with `github-setup.sh`. Turn on Cloudflare logs and observability. Dry run first, ask before `--apply`.

### M8: Bug hunt and AI review (needs M4)
Enable the AI review workflow. Run the `bug-hunt` skill across the codebase. Output a ranked report and open one GitHub issue per confirmed bug with reproduction steps. Fix nothing in this module.

### M9: Move from Vercel to Cloudflare (needs M3)
Vercel keeps serving production until the final switch; every step is reversible.
1. Map every Vercel feature in use to its Cloudflare equivalent, from the official docs, and show the table before changing anything: framework build (Next.js to the `@opennextjs/cloudflare` adapter), env vars (names via `vercel env ls`), Vercel KV / Postgres / Blob to KV / D1 or Hyperdrive / R2, cron jobs to Cron Triggers, middleware, image optimization, redirects and headers, analytics. Flag anything with no clean equivalent.
2. Build the app on Workers in a branch, with `wrangler.jsonc` defining `staging` and `production`, each with its own bindings.
3. Data: if data lives in a Vercel-managed store, write a one-off copy script into the staging stores first. Production data is copied only at cutover, after a fresh backup.
4. Verify on staging: run the M3 characterization tests and E2E against the staging URL. They must pass with the same results as against Vercel.
5. Cutover plan (the owner approves before it starts): lower DNS TTL a day ahead if possible, freeze writes or sync data, switch the domain to the Cloudflare Worker, watch logs for 30 minutes, keep Vercel deployed untouched for 7 days as rollback.
6. Rollback: a written one-step procedure to point the domain back to Vercel.
If the move is too big for one night, move the smallest independent route first behind a Cloudflare route and leave the rest on Vercel; each further piece becomes a story.

### M10: Tighten
Switch lint and typecheck from warn-only to required once warnings are fixed or explicitly waived. Update PROGRESS.md with the final state and a list of follow-up stories.

## Definition of done (tonight)
M0 to M8 merged or explicitly deferred with a reason, CI green on `main`, staging deploy working, production behind the owner's approval, and `PROGRESS.md` showing exactly what is left.
