# ADR 0001: Supabase Postgres instead of D1
- Status: accepted
- Date: 2026-10-31

## Context
The default stack uses D1. The live dashboards already run on Supabase: Auth, Postgres tables with RLS, and the integration tokens. Moving all of it to D1 means rewriting auth and permissions for no user-facing gain.

## Decision
- A project may keep Supabase as its database and auth provider.
- Workers reach Postgres through Hyperdrive when they run SQL. Auth and simple reads can use `supabase-js` over HTTPS without Hyperdrive.
- Schema changes are SQL files in `migrations/`, applied in file-name order. CI sets `db-engine: postgres`, which applies every migration to a throwaway Postgres with stand-ins for the Supabase roles and `auth.uid()`.
- Merged migrations are immutable, same rule as D1.

## Consequences
- The D1 migration check is replaced by the Postgres one; staging needs its own Supabase project or branch.
- Hyperdrive must use a Supabase connection mode it supports; check the current Cloudflare and Supabase docs when wiring it.
- Backups are Supabase's, not Cloudflare's: the owner confirms a backup before any schema change.
