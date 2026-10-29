---
name: bug-hunt
description: Proactive bug hunt over a Cloudflare Workers/D1 project. Use before a release or when asked to "look for bugs", "audit", or "find problems". Checks edge cases, error paths, auth, input validation, N+1 queries and missing D1 indexes, outputs a ranked report, and opens one issue per confirmed bug.
---

# Bug hunt

Read first, prove second, report third. A suspicion is not a bug until it is confirmed.

## Hard rules
- Read-only on the code: this skill finds and reports, it does not fix. Fixes are separate stories with the `debug` skill.
- Never run write queries or destructive requests against staging or production. Reproduce locally (`wrangler dev`, local D1) or with tests.
- Never put a secret value in a report or an issue. Say where it is, nothing more.
- Do not touch the schema or dependencies. Index suggestions are proposals that need the owner's approval and an ADR.
- Check the current Cloudflare docs before claiming a limit or an API behavior.

## 1. Scope
Read `docs/architecture.md`, `CLAUDE.md`, and the routes/handlers. Ask the owner only if the scope is unclear (whole repo, one area, since a given tag). Default: the whole `src/` and `migrations/`.

## 2. Hunt, by category
Go through each category, with the code in front of you.

**Edge cases**: empty, null, missing, huge, negative, duplicate, unicode, time zones, off by one, pagination boundaries, concurrent requests, retries and idempotency.
**Error paths**: unhandled promise rejections, missing `await`, errors swallowed by `catch`, error responses that leak internals, partial failure (the D1 write succeeded and the R2 write failed), `ctx.waitUntil` work that can fail silently.
**Auth**: every route has an explicit auth decision, authorization checks the owner of the resource (not only that the user is logged in), tokens and sessions expire, no secrets in logs, CORS and CSRF where cookies are used, admin routes not reachable by default.
**Input validation**: every external input (body, query, headers, path params, file uploads, webhook payloads) is parsed and validated before use, size limits, content types, SQL always through bound parameters (`.bind()`), no string concatenation into SQL, no open redirects, safe file names for R2 keys.
**N+1 and cost**: queries inside loops, one query per row, missing `LIMIT`, `SELECT *` on wide tables, repeated identical reads that belong in KV or a cache, unbatched writes (use `D1Database.batch`).
**D1 indexes**: for each `WHERE`, `JOIN`, and `ORDER BY`, is there an index that serves it? Check with `EXPLAIN QUERY PLAN` on the local database (a `SCAN` on a large table is a finding). D1 bills rows read, so this is also cost.
**Migrations**: an edited merged migration, a migration that is not safe to run twice, a destructive migration without a backup note, drift between `migrations/` and what the code expects.
**Config**: bindings missing in one environment, the same D1 or R2 used by two environments, secrets referenced but not documented in `.dev.vars.example`.

## 3. Confirm
For each suspicion try to prove it: a failing test, a local reproduction with exact steps, or a concrete trace through the code with file and line. Confirmed = reproduced or provable from the code. Everything else goes in "Unconfirmed" with what is needed to confirm it.

## 4. Rank
Severity: **critical** (data loss, auth bypass, secret exposure), **high** (wrong results for real users, crash on a common path), **medium** (edge case, cost, missing index on a growing table), **low** (hardening). Within a severity, rank by how likely a real user hits it.

## 5. Report
Write `docs/bug-hunt/<YYYY-MM-DD>.md` in the repo (or ask where the owner wants it) with: scope, date and commit, a ranked table (id, severity, title, location, status), then one section per confirmed bug (what, where as file:line, how to reproduce, impact, suggested fix direction), then "Unconfirmed", then "Checked and fine" (so the owner knows what was covered).

## 6. Issues
After the report exists, open one GitHub issue per confirmed bug with `gh issue create`:
- first check for duplicates: `gh issue list --search "<title keywords>" --state all`
- title `[bug-hunt] <short title>`, label `bug` (and `bug-hunt` if the label exists), body = the bug section from the report plus the severity
- never open issues for unconfirmed items
- if `gh` is not logged in, stop and give the owner the exact login command and a ready list of issues to paste
Finish with the counts per severity and links to the issues.
