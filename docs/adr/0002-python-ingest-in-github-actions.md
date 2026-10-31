# ADR 0002: Python ingest in GitHub Actions
- Status: accepted
- Date: 2026-10-31

## Context
The default strategy runs scheduled work in Cron Triggers on Workers. Data ingest here is Python (ad platform APIs, Salla, PyAirbyte), which does not fit the Workers runtime or its CPU limits.

## Decision
- Ingest runs in a scheduled GitHub Actions workflow, writes to Supabase, and never needs a human machine.
- Cron Triggers are only for light work inside the Worker (cache refresh, cleanup).
- A source with no API credential yet (TikTok, pulled through an MCP connector) is the one exception: a scheduled Claude task pulls it and hands the raw file to the same pipeline. When the API is approved it moves into the Action.

## Consequences
- Platform credentials for ingest are GitHub Actions secrets (or Vault, see ADR 0003).
- CI tests the Python code (`python-version`, `python-test-command`, `python-lint-command` in `ci.yml`).
- No more pushes from an outside machine straight to `main`.
