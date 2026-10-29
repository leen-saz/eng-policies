# Architecture

> The source of truth for design decisions. Claude reads this before any design decision and may not leave it, add a dependency, change the database schema, or rewrite working code without the owner's explicit approval. Record every significant decision as an ADR in `docs/adr/`.

## 1. Overview
One paragraph: what the system is and the main flow of a request.

## 2. Stack (core architecture)
| Concern | Choice | Why |
| --- | --- | --- |
| UI and API | Cloudflare Workers | |
| Data | Cloudflare D1 (migrations in `migrations/`) | |
| Files | Cloudflare R2 | |
| Fast lookups | Cloudflare KV (only if needed) | |
| Language and test tools | TypeScript, Vitest, Playwright | |

## 3. Environments
| Environment | Worker | D1 | R2 | Deploy |
| --- | --- | --- | --- | --- |
| local | `wrangler dev` | local SQLite | local | manual |
| preview | `<app>-preview` | own database | own bucket | every PR |
| staging | `<app>-staging` | own database | own bucket | merge to `main` |
| production | `<app>` | own database | own bucket | approval in the `production` environment |

## 4. Components and boundaries

## 5. Data model
Tables, key columns, and the indexes that serve each query. Any change needs a migration, an ADR, and owner approval.

## 6. Security
Authentication, authorization, input validation, secrets handling (names only, never values).

## 7. Observability
Logs (`wrangler tail`), error reporting, health endpoint.

## 8. Forbidden without approval
- Leaving the stack above
- Adding or upgrading a dependency
- Changing the schema or editing a merged migration
- Rewriting working code outside the current story

## 9. Open questions
