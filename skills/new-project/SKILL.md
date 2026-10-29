---
name: new-project
description: Start a brand new project on the owner's stack (GitHub + Cloudflare Workers/D1/R2/KV, planned with BMAD). Use when the user says "we're building X", "start a new project", or "new app for X". Installs eng-policies, sets up GitHub and Cloudflare with confirmation, runs BMAD planning, and stops for approval before any code.
---

# New project

Goal: a project that follows eng-policies from the first commit, with an approved plan before any code exists.

## Hard rules
- Do not write application code in this skill. The last step is a stop for the owner's approval.
- Ask before: creating the GitHub repo, pushing, changing any GitHub or Cloudflare setting.
- Never write, print or commit a secret. Print the exact `gh secret set NAME` / `wrangler secret put NAME` command for the owner to run.
- Check the current Cloudflare and GitHub docs before writing any config. Do not rely on memory for flags, file names or limits.

## 1. Find the installer
Use the first that exists: `${CLAUDE_PLUGIN_ROOT}/install/install.sh` (plugin install), `$ENG_POLICIES_HOME/install/install.sh`, `~/eng-policies/install/install.sh`. If none exists, ask the owner where the eng-policies checkout is. Call the folder `$POLICIES`.

## 2. Ask goals and users (one short round)
Use AskUserQuestion, at most 4 questions, only what the plan needs:
- What is it, in one sentence, and what does success look like?
- Who are the users and how many (order of magnitude)?
- Must-have features for the first release (the smallest version that is useful)?
- Constraints: deadline, budget ceiling, data that is sensitive, existing systems it must talk to.
If the owner already answered some of these in the request, do not ask them again.

## 3. Create the folder and install (`--mode new`)
1. Pick a slug (lowercase, dashes) and the target folder. Confirm the folder if it is not obvious.
2. `git init -b main` if it is not a repository.
3. Dry run first, and show the list: `bash "$POLICIES/install/install.sh" <dir> --mode new --dry-run`
4. After the owner agrees: `bash "$POLICIES/install/install.sh" <dir> --mode new --name <slug>`
5. Create the branch `chore/bootstrap`, run the project's own gates once (`npm install`, `npm run lint`, `npm run typecheck`, `npm run test:unit`, `npm run test:integration`, `npm run build`) and commit. Fix problems in the starter, never by weakening a gate.

## 4. GitHub and Cloudflare setup (each step needs an explicit yes)
Always run the dry run first, show the output, then ask.
1. Create the repo (ask visibility: public or private; mention that environment required reviewers on a private repo need GitHub Pro or Team): `gh repo create <owner>/<slug> --<visibility> --source <dir> --remote origin`. Ask first. Then push the bootstrap branch and open a PR.
2. `bash "$POLICIES/install/github-setup.sh" <owner>/<slug>` (dry run), then with `--apply` after the owner agrees. Relay the list of secrets the owner must set.
3. `bash "$POLICIES/install/cloudflare-setup.sh" <dir>` (dry run), then with `--apply` after the owner agrees.
4. If the policies repo is private, remind the owner to allow other repositories to call its workflows (Settings > Actions > General > Access).
If `gh auth status` or `npx wrangler whoami` fails, stop and tell the owner exactly which login command to run in their own terminal. Do not ask for tokens in chat.

## 5. BMAD planning: PRD, then architecture, then stories
Use BMAD-METHOD agents if the project has them installed (`.bmad-core/` or `_bmad/`): the analyst/PM for the PRD, the architect for the architecture, the scrum master for stories. Otherwise write the documents directly in the templates that were installed.
1. `docs/prd.md`: problem, goals, users, functional and non-functional requirements, epics, risks. Mark every assumption.
2. `docs/architecture.md`: confirm the default stack (Workers + D1 + R2, KV only if needed), data model with the index for each query, auth, security, the three environments. Each significant decision becomes an ADR in `docs/adr/`.
3. `docs/stories/`: small stories (one PR each) with acceptance criteria and a test plan. The first story is the thinnest end to end slice, deployed to staging.
4. Fill the `CLAUDE.md` placeholders (summary, architecture pointer, forbidden changes, commands).
Commit the documents on a branch and open a PR so the owner can comment.

## 6. Stop
End with a short summary: what exists, what the owner still has to do (secrets, approvals), and the exact question: "Approve the PRD, architecture and stories so I can start story 1?". Do not start story 1 until the owner says yes.
