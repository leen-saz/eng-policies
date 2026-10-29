# {{PROJECT_NAME}}

> Template from `eng-policies`. Fill every placeholder. This file is read by Claude at the start of each session. The global rules in `~/.claude/CLAUDE.md` always apply.

## Project summary
{{ONE_PARAGRAPH: what this project does, who uses it, and what success looks like.}}

## Core architecture
The source of truth is `docs/architecture.md`. Read it before any design decision.
Summary: {{ONE_LINE: for example "Worker (UI + API) on Cloudflare, D1 for data, R2 for files, KV for lookups"}}.
Decisions are recorded in `docs/adr/`.

## Forbidden changes (need explicit owner approval)
- Leaving the architecture described in `docs/architecture.md`
- Adding or upgrading a dependency
- Changing the database schema or editing an existing migration
- Rewriting working code that is not part of the current story
- Changing CI, branch protection, or environment settings
- {{PROJECT_SPECIFIC_FORBIDDEN_ITEM}}

## Commands
Detected by the installer. Edit if wrong.

| Task | Command |
| --- | --- |
| Install | `{{INSTALL_CMD}}` |
| Dev server | `{{DEV_CMD}}` |
| Lint | `{{LINT_CMD}}` |
| Typecheck | `{{TYPECHECK_CMD}}` |
| Unit tests | `{{UNIT_CMD}}` |
| Integration tests | `{{INTEGRATION_CMD}}` |
| E2E tests | `{{E2E_CMD}}` |
| Build | `{{BUILD_CMD}}` |
| Migrate local D1 | `{{MIGRATE_LOCAL_CMD}}` |
| Deploy staging | automatic on merge to `main` |
| Deploy production | approval in the GitHub `production` environment |

## Working agreement
- One branch and one PR per story in `docs/stories/`.
- Update `docs/adoption/PROGRESS.md` when a gate is moved from `warn-only` to blocking.
