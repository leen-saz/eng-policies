#!/usr/bin/env bash
# GitHub setup for a project that adopted eng-policies.
#
#   github-setup.sh <owner/repo> [--apply] [--reviewer <github-handle>] [--branch main] [--approvals N]
#
# Without --apply it only PRINTS what it would do (a dry run) and changes nothing.
# With --apply it asks for a typed "yes", then uses `gh` to:
#   1. create a ruleset on the default branch: pull request required, check "ci / gate" required,
#      no force-push (non fast forward), no branch deletion. Required approvals default to 0 because a
#      solo owner cannot approve their own PR; use --approvals 1 as soon as there is a second person.
#   2. create the environments `staging` and `production` (production requires you as reviewer)
# It never reads or prints a secret value. At the end it prints the exact `gh secret set` commands for YOU to run.
#
# Plan limits (GitHub docs): required reviewers on environments and environment secrets in a PRIVATE
# repository need GitHub Pro (personal account) or Team (organization). Public repos have them on every plan.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

REPO=""
APPLY=0
REVIEWER=""
BRANCH="main"
APPROVALS="0"

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --reviewer) REVIEWER="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --approvals) APPROVALS="${2:-}"; shift 2 ;;
    -h | --help) sed -n '2,17p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) REPO="$1"; shift ;;
  esac
done

[ -n "$REPO" ] || die "usage: github-setup.sh <owner/repo> [--apply]"
case "$APPROVALS" in 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9) ;; *) die "--approvals must be a number from 0 to 9" ;; esac
case "$REPO" in */*) ;; *) die "repo must look like owner/repo" ;; esac
OWNER="${REPO%%/*}"
[ -n "$REVIEWER" ] || REVIEWER="$OWNER"

command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is required: https://cli.github.com"

RULESET_NAME="eng-policies: protect $BRANCH"

# The ruleset body. The required check is "ci / gate": caller job id `ci` + the reusable job `gate`.
ruleset_json() {
  cat <<EOF
{
  "name": "$RULESET_NAME",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/$BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": $APPROVALS,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [ { "context": "ci / gate" } ]
      }
    }
  ]
}
EOF
}

print_secrets() {
  say ""
  say "Secrets YOU must set (the values are never passed through this script or through chat):"
  info "# Cloudflare, used by preview and deploy. Create the token in the Cloudflare dashboard with the"
  info "# 'Edit Cloudflare Workers' template plus 'D1 Edit' and 'Workers R2 Storage Edit', scoped to one account."
  info "gh secret set CLOUDFLARE_API_TOKEN  --repo $REPO"
  info "gh secret set CLOUDFLARE_ACCOUNT_ID --repo $REPO"
  info "# Optional: separate tokens per environment (they override the repository secret for that environment)"
  info "gh secret set CLOUDFLARE_API_TOKEN  --repo $REPO --env staging"
  info "gh secret set CLOUDFLARE_API_TOKEN  --repo $REPO --env production"
  info "# Claude review on PRs (the review is skipped, not failed, when this is missing)"
  info "gh secret set ANTHROPIC_API_KEY     --repo $REPO"
  say ""
  say "Each command prompts for the value. Runtime secrets of the Worker itself:"
  info "npx wrangler secret put NAME --env staging"
  info "npx wrangler secret put NAME --env production"
}

say "Repository: $REPO   protected branch: $BRANCH   production reviewer: $REVIEWER"
say ""
say "Plan (nothing is changed unless you pass --apply):"
info "1. ruleset '$RULESET_NAME': PR required ($APPROVALS approvals, threads resolved), check 'ci / gate' required and up to date, no force-push, no deletion"
info "2. environment 'staging' (no reviewers)"
info "3. environment 'production' (required reviewer: $REVIEWER, deploys only from $BRANCH)"
say ""
say "Ruleset body:"
ruleset_json | sed -e 's/^/    /'

if [ "$APPLY" -eq 0 ]; then
  print_secrets
  say ""
  say "Dry run only. Re-run with --apply to make these changes."
  exit 0
fi

gh auth status >/dev/null 2>&1 || die "gh is not logged in. Run: gh auth login"

say ""
printf 'Apply these changes to %s on GitHub? Type "yes" to continue: ' "$REPO"
read -r answer
[ "$answer" = "yes" ] || die "cancelled, nothing was changed."

# visibility decides what GitHub allows
visibility="$(gh api "repos/$REPO" --jq '.private' 2>/dev/null || echo unknown)"
if [ "$visibility" = "true" ]; then
  warn "private repository: environment required reviewers and environment secrets need GitHub Pro/Team. If step 3 fails with a plan error, upgrade the plan or make the repo public."
fi

# 1. ruleset: update the one we created earlier, otherwise create it
existing_id="$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$RULESET_NAME\") | .id" 2>/dev/null | head -1 || true)"
tmp_json="$(mktemp "${TMPDIR:-/tmp}/engpol-ruleset.XXXXXX")"
trap 'rm -f "$tmp_json"' EXIT
ruleset_json >"$tmp_json"
if [ -n "$existing_id" ]; then
  gh api --method PUT "repos/$REPO/rulesets/$existing_id" --input "$tmp_json" >/dev/null
  say "updated ruleset #$existing_id"
else
  gh api --method POST "repos/$REPO/rulesets" --input "$tmp_json" >/dev/null
  say "created ruleset"
fi

# 2. staging environment
gh api --method PUT "repos/$REPO/environments/staging" >/dev/null
say "environment staging: ready"

# 3. production environment with a required reviewer
reviewer_id="$(gh api "users/$REVIEWER" --jq '.id')"
prod_json="$(mktemp "${TMPDIR:-/tmp}/engpol-env.XXXXXX")"
cat >"$prod_json" <<EOF
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [ { "type": "User", "id": $reviewer_id } ],
  "deployment_branch_policy": { "protected_branches": true, "custom_branch_policies": false }
}
EOF
if gh api --method PUT "repos/$REPO/environments/production" --input "$prod_json" >/dev/null; then
  say "environment production: ready (required reviewer: $REVIEWER)"
else
  rm -f "$prod_json"
  die "could not configure the production environment (see the plan note above)."
fi
rm -f "$prod_json"

print_secrets
say ""
say "Done."
