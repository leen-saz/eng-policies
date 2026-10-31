# ADR 0004: Production gate on GitHub Free
- Status: proposed
- Date: 2026-10-31

## Context
The strategy requires a protected `main` and an owner approval before production deploys. On GitHub Free, private repositories do not get branch rulesets or environment required reviewers. The owner chose not to pay for a plan now.

## Decision
- Only the owner has write access to the project repos.
- The deploy workflow runs only on `main`, only after `ci / gate` passes in the same run, through the `production` environment restricted to the `main` branch.
- Claude may deploy to staging on its own and asks the owner in one line before each production deploy.

## Consequences
- Weaker than a real ruleset: a direct push to `main` is possible, though the deploy still waits for CI.
- Revisit when a second person gets write access, or when the owner buys a plan. Confirm against the current GitHub plan docs which plan unlocks required reviewers for private repos before buying.
