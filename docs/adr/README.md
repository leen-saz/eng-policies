# Policy ADRs

Decisions that change the default strategy for every project that adopts eng-policies.
A project points to these from its own `docs/adr/` instead of copying them, and records only its project-specific choices.

| ADR | Decision |
|---|---|
| [0001](0001-supabase-postgres-instead-of-d1.md) | Supabase Postgres is allowed instead of D1, reached from Workers through Hyperdrive |
| [0002](0002-python-ingest-in-github-actions.md) | Python data ingest runs in scheduled GitHub Actions, not Cron Triggers |
| [0003](0003-integration-tokens-in-supabase-vault.md) | Third-party integration tokens live in Supabase Vault; system secrets stay in GitHub and Cloudflare |
| [0004](0004-production-gate-on-github-free.md) | Production gate on GitHub Free for private repos |
