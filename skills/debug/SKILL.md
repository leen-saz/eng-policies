---
name: debug
description: Systematic debugging for Cloudflare Workers/D1/R2 projects. Use when something is broken, failing, flaky or "works locally but not deployed": read logs, reproduce, find the root cause, write a regression test, then fix. Never patch the symptom.
---

# Debug

The order is fixed. Skipping a step is how bugs come back.

## Hard rules
- Do not fix before you can reproduce, and do not fix before you know the root cause.
- Do not patch a symptom (a `try/catch` that swallows the error, a retry, a longer timeout, a null check that hides bad data) unless the root cause is that exact missing handling.
- Do not add a dependency, change the schema, or rewrite working code to fix a bug without the owner's approval. If the root cause needs one, stop and explain.
- Never print secrets from logs, `.dev.vars`, or environment dumps. Redact before quoting.
- Check the current Cloudflare docs before relying on an API behavior or a limit.

## 1. Frame it
Write down in two lines: what is expected, what happens instead, and in which environment (local, preview, staging, production). Get the exact error text, URL, request, and time if you can. Check `git log` for what changed recently.

## 2. Read the logs
- Deployed Worker: `npx wrangler tail --env <env> --format pretty` while triggering the problem. Filter with `--status error` or `--search <text>` when noisy.
- CI failure: read the failing job log from the first error, not the last line.
- D1: `npx wrangler d1 execute DB --env <env> --local --command "<read only SQL>"` for local state. Do not run writes on a remote database while debugging.
Note what the logs say and what they do NOT say.

## 3. Reproduce
- Locally: `npx wrangler dev --env staging` (local D1 and R2), then send the same request. Apply migrations first: `npx wrangler d1 migrations apply DB --env staging --local`.
- If it only fails when deployed: compare what differs (bindings, vars, secrets by name, compatibility date, data) and reproduce the difference locally.
- Minimize: shrink the input and the steps until it still fails.
If you cannot reproduce, say so and list what you would need (a log line, an input, access), instead of guessing.

## 4. Find the root cause
Ask "why" until you reach something that, if changed, makes the whole class of failure impossible. Typical Workers/D1 causes: unhandled rejection in `ctx.waitUntil`, missing `await`, a binding missing in one environment (bindings are not inherited between environments), a migration applied locally but not remotely, a query without an index that now scans too many rows, a body read twice, a limit (CPU time, subrequests, request size).
State the root cause in one sentence and the evidence for it.

## 5. Write the regression test first
Add a test that fails for exactly the reason you found (unit when it is pure logic, integration when it needs D1, E2E only when it needs the deployed app). Run it and watch it fail. Commit message later will name this test.

## 6. Fix
The smallest change that makes the test pass and removes the root cause. One branch, one small PR: `fix/<issue>-<slug>`. No drive-by refactors.

## 7. Verify
Run the new test, then the whole suite and lint and typecheck. Reproduce the original scenario once more by hand. A task is not done until tests pass locally and in CI.

## 8. Report
Short summary: symptom, root cause, the test that guards it, the fix, and anything related you noticed but did not change.
