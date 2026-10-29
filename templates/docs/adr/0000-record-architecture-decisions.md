# ADR 0000: Record architecture decisions

- Status: accepted
- Date: __DATE__

## Context
Decisions about architecture, dependencies and the database schema are easy to forget and expensive to reverse.

## Decision
Every significant decision is recorded as a short ADR in this folder, numbered in order (`0001-...`). An ADR is required for: a new dependency, a schema change, a change to the core architecture, and a new environment or binding.

## Template for the next ADRs
```markdown
# ADR 000N: <decision>
- Status: proposed | accepted | superseded by ADR 000M
- Date:

## Context
## Decision
## Consequences
```

## Consequences
Decisions are searchable and reviewable in a PR. `docs/architecture.md` stays short because the reasoning lives here.
