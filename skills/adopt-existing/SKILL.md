---
name: adopt-existing
description: Bring an EXISTING project (brownfield) under eng-policies in small independent modules, one PR each, without breaking what works. Use when the user says "adopt eng-policies in this repo", "bring this project up to standard", or "set up CI and policies for the existing project".
---

# Adopt eng-policies in an existing project (brownfield)

Principle: every module is independent, small, reversible and ships as its own PR. The project must keep working after each one. Nothing is rewritten, no dependency is added, and no schema is changed unless the owner approves it.

> Note for the owner: this is the first version of the brownfield flow. If you have a more specific "Prompt 2" adoption flow, replace the modules below with it. The rules in "Hard rules" stay.

## Hard rules
- Never overwrite an existing file: the installer writes `*.policy-new` for conflicts, and you merge by hand with the owner.
- Never leave the current architecture, add a dependency, change the schema, or rewrite working code without the owner's explicit approval. If a module seems to need it, stop and ask.
- Lint and typecheck start as `warn-only`. Every other gate is blocking from day one.
- No secrets in code, logs or chat. If a scan finds one, report its location only, and tell the owner to rotate it.
- Ask before: creating or changing GitHub or Cloudflare settings, pushing, opening PRs.
- Track everything in `docs/adoption/PROGRESS.md`.

## Module 0: assess (read only, no PR)
Read, do not change. Produce a short report for the owner:
- stack: language, package manager, test runner, frameworks, how it is deployed today
- is there a Worker/wrangler config, D1, R2, KV? Which environments exist?
- CI today (workflows, what they run), branch rules, secrets in use (names only)
- tests: what exists, rough coverage of the risky paths, how long they take
- run the current lint, typecheck, tests and build once and record the baseline (pass/fail, counts)
- dry run of the installer: `bash <policies>/install/install.sh . --mode existing --dry-run`
Ask the owner which modules to do and in what order. Default order below.

## Module 1: install the policies (mode existing)
Branch `chore/adopt-eng-policies`. Run `install.sh . --mode existing`, then walk through every `*.policy-new` with the owner and merge by hand (wrangler config: add `env.preview/staging/production` blocks, each with its own D1 and R2). Commit the result. This module only adds files.

## Module 2: CI baseline green
Open the PR so the new `ci` workflow runs. Goal: the `ci / gate` check is green with lint and typecheck as warn-only. If a blocking gate fails (tests, build, audit, secret scan), classify each failure: real bug, flaky test, or environment difference, and fix the smallest thing. A flaky test gets a ticket and a quarantine note in PROGRESS.md, never a silent skip. Record the baseline numbers.

## Module 3: secrets hygiene
Run the secret scan on the full history once (`secret-scan-full-history: true` in a temporary run, or `gitleaks git` locally). For each finding: location only, owner rotates the secret, then add a `.gitleaksignore` entry with a comment only after rotation. Move any secret from code to `.dev.vars` (local) and `wrangler secret put` / GitHub Secrets. Give the owner the exact commands.

## Module 4: environments
Make sure each environment (preview, staging, production) has its own D1 and R2 in the wrangler config. Create the resources with `cloudflare-setup.sh` (dry run first, then `--apply` after approval). Create the GitHub environments and ruleset with `github-setup.sh` (dry run first). Production must require the owner as reviewer. Do not change what production runs on before the owner agrees.

## Module 5: migrations under control
If the project has a D1 schema: put it under `migrations/` as numbered files without changing the live schema (a baseline that matches production exactly, verified against a dump of the schema). Enable the migration check. If the schema is not in D1, skip.

## Module 6: tests around the risky paths
Add characterization tests for the most important flows (the ones that lose money or data if they break), without changing behavior. Add the integration and E2E skeleton if missing. One PR per flow.

## Module 7: preview, deploy and review workflows
Enable `preview` (PR previews and E2E), `deploy` (staging automatic, production by approval), `ai-review` (needs the ANTHROPIC_API_KEY secret, owner sets it), `codeql` (needs GitHub Code Security on private repos). Check each with a real PR before relying on it.

## Module 8: flip warn-only to blocking
Per gate (lint, then typecheck): list the violations, fix by area with small PRs (auto-fixers first, behavior changes never mixed in), then set the mode to `block`, update PROGRESS.md. Never do this in one giant PR.

## Module 9: docs backfill
Write `docs/architecture.md` from the code as it is today (describe, do not redesign), add ADRs for decisions that are still visible in the code, and fill `CLAUDE.md` (summary, forbidden changes, commands).

## After each module
Update `docs/adoption/PROGRESS.md`, run the project's gates, open the PR, and give the owner a two line summary: what changed, what to check. Stop and ask before the next module.
