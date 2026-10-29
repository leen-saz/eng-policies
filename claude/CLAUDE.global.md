# Global engineering rules for Claude

Installed by `eng-policies` to `~/.claude/CLAUDE.md`. These apply to every project. A project's own `CLAUDE.md` can add rules but never relax these.

## Git and workflow
- Never work directly on `main`. Create one branch per task (`feat/<story-id>-<slug>` or `fix/<issue>-<slug>`).
- Keep PRs small: one story per PR.
- Use conventional commits (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`, `test:`, `refactor:`), one commit per logical change.
- Never push, create a repo, or change any GitHub or Cloudflare setting without asking first.

## Architecture and scope
- Read `docs/architecture.md` before any design decision.
- Do not do any of the following without explicit approval from the owner:
  - leave the core architecture
  - add a dependency
  - change the database schema
  - rewrite working code
- If the task seems to require one of these, stop, explain why, and ask.

## Definition of done
- A task is not done until tests pass locally AND in CI.
- Every bug fix ships with a regression test that fails before the fix and passes after.
- Never mark work complete if tests were skipped, disabled, or weakened to get green.

## Debugging
Debug systematically, in this order:
1. Read logs (`wrangler tail`).
2. Reproduce locally (`wrangler dev`).
3. Find the root cause.
4. Add a regression test.
5. Fix.
Do not patch symptoms (for example a `try/catch` that swallows the error).

## Cloudflare
- Follow Cloudflare's official best practices.
- Check the current docs before using any API, flag, or limit. Do not rely on memory.
- Prefer `wrangler.jsonc`. Each environment declares its own bindings (D1, R2, KV, vars are not inherited between environments).
- Use a separate D1 database and R2 bucket for staging and production.

## Secrets
- No secrets in code, logs, commit messages, or chat.
- When a secret is needed, write the exact command (`gh secret set NAME` or `wrangler secret put NAME`) for the owner to run. Never run it with a value yourself.
- If you see a secret value anywhere, stop and tell the owner so it can be rotated.

## Communication
- Be direct about what was verified and what was not.
- When blocked, report what was tried and what is needed, instead of guessing.
