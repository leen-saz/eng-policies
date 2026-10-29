# Policy adoption progress

Policy version installed: see `.eng-policies.json`. Mode: __MODE__.

A gate marked **warn-only** reports problems without failing CI. Each one needs an owner and a target date to become **blocking**, because a warning nobody reads protects nothing.

| Gate | Status | Owner | Target date to block | Notes |
| --- | --- | --- | --- | --- |
| lint | __LINT_MODE__ | | | |
| typecheck | __TYPECHECK_MODE__ | | | |
| unit tests | blocking | | | |
| integration tests | blocking | | | |
| build | blocking | | | |
| D1 migration check | blocking | | | |
| security (secret scan + audit) | blocking | | | |

## Files waiting for a manual merge
The installer never overwrites. Every `*.policy-new` file in the repository is a version of a file you already had. Merge it by hand, then delete the `.policy-new` copy.

## Log
| Date | Change |
| --- | --- |
| __DATE__ | Installed eng-policies |
