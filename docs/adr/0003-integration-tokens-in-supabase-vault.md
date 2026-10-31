# ADR 0003: Integration tokens in Supabase Vault
- Status: accepted
- Date: 2026-10-31

## Context
The default strategy keeps every secret in GitHub and Cloudflare. Integration tokens (ad platforms, Salla) are connected and rotated from the dashboard's own connections tab, so they change at runtime and cannot live in CI secrets.

## Decision
- System secrets (Cloudflare API token, Supabase service key, webhook secrets) stay in GitHub and Cloudflare secrets.
- Integration tokens set from the UI are stored in Supabase Vault.
- Vault is read through a dedicated Postgres role or `security definer` function that can read only the needed secrets, never by handing `service_role` to the Worker.

## Consequences
- A migration creates the role and functions; CI checks it like any other migration.
- Rotating an integration token needs no deploy.
