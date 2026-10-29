#!/usr/bin/env bash
# Cloudflare setup for a project that adopted eng-policies.
#
#   cloudflare-setup.sh <project-dir> [--apply]
#
# Reads the app name from wrangler.jsonc and prepares, per environment (preview, staging, production):
#   - one D1 database   <app>-<env>-db
#   - one R2 bucket     <app>-<env>-files
# Without --apply it only PRINTS the wrangler commands. With --apply it asks for a typed "yes", runs
# them, then writes the new D1 IDs into wrangler.jsonc (replacing the all-zero placeholder IDs).
# It never prints or stores an API token: authenticate yourself first with `wrangler login`
# (or export CLOUDFLARE_API_TOKEN in your own shell).
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

DIR=""
APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    -h | --help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) DIR="$1"; shift ;;
  esac
done
[ -n "$DIR" ] || die "usage: cloudflare-setup.sh <project-dir> [--apply]"
[ -d "$DIR" ] || die "no such directory: $DIR"
need_node

CONFIG="$DIR/wrangler.jsonc"
[ -f "$CONFIG" ] || die "$CONFIG not found. Run install.sh first (or merge wrangler.jsonc.policy-new)."

# placeholder IDs written by the template
PLACEHOLDER_PREVIEW="00000000-0000-0000-0000-000000000001"
PLACEHOLDER_STAGING="00000000-0000-0000-0000-000000000002"
PLACEHOLDER_PRODUCTION="00000000-0000-0000-0000-000000000003"

APP="$(sed -n 's/^[[:space:]]*"name":[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG" | head -1)"
[ -n "$APP" ] || die "could not read the app name from $CONFIG"

placeholder_for() {
  case "$1" in
    preview) printf '%s' "$PLACEHOLDER_PREVIEW" ;;
    staging) printf '%s' "$PLACEHOLDER_STAGING" ;;
    production) printf '%s' "$PLACEHOLDER_PRODUCTION" ;;
  esac
}

say "App: $APP   config: $CONFIG"
say ""
say "Commands (run from $DIR):"
for env in preview staging production; do
  info "npx wrangler d1 create $APP-$env-db"
  info "npx wrangler r2 bucket create $APP-$env-files"
done
say ""
say "Then each database ID replaces its placeholder in wrangler.jsonc, and the migrations are applied:"
for env in preview staging production; do
  info "npx wrangler d1 migrations apply DB --env $env --remote"
done
say ""
say "Secrets for the Worker itself are set by you: npx wrangler secret put NAME --env <env>"

if [ "$APPLY" -eq 0 ]; then
  say ""
  say "Dry run only. Re-run with --apply to create the resources."
  exit 0
fi

command -v npx >/dev/null 2>&1 || die "npx is required"
say ""
printf 'Create %s D1 databases and R2 buckets in your Cloudflare account now? Type "yes": ' "3"
read -r answer
[ "$answer" = "yes" ] || die "cancelled, nothing was created."

(cd "$DIR" && npx wrangler whoami >/dev/null 2>&1) || die "wrangler is not logged in. Run: npx wrangler login"

new_id_of() { # extracts a UUID from the output of `wrangler d1 create`
  grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1
}

for env in preview staging production; do
  db="$APP-$env-db"
  bucket="$APP-$env-files"
  ph="$(placeholder_for "$env")"

  # D1: reuse an existing database with that name, otherwise create it
  existing="$(cd "$DIR" && npx wrangler d1 info "$db" --json 2>/dev/null | new_id_of || true)"
  if [ -n "$existing" ]; then
    id="$existing"
    say "D1 $db already exists ($id)"
  else
    out="$(cd "$DIR" && npx wrangler d1 create "$db" 2>&1)" || { printf '%s\n' "$out" >&2; die "wrangler d1 create $db failed"; }
    id="$(printf '%s' "$out" | new_id_of)"
    [ -n "$id" ] || { printf '%s\n' "$out" >&2; die "could not read the new database ID for $db"; }
    say "D1 $db created ($id)"
  fi

  # R2: creating an existing bucket fails harmlessly, so check the list first
  if (cd "$DIR" && npx wrangler r2 bucket list 2>/dev/null | grep -q "$bucket"); then
    say "R2 $bucket already exists"
  else
    (cd "$DIR" && npx wrangler r2 bucket create "$bucket") || die "wrangler r2 bucket create $bucket failed"
    say "R2 $bucket created"
  fi

  # write the ID into wrangler.jsonc (no sed -i: portable)
  if grep -q "$ph" "$CONFIG"; then
    sed -e "s/$ph/$id/g" "$CONFIG" >"$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
    say "wrangler.jsonc: $env database_id filled in"
  fi
done

say ""
printf 'Apply the D1 migrations to the three remote databases now? Type "yes": '
read -r answer2
if [ "$answer2" = "yes" ]; then
  for env in preview staging production; do
    (cd "$DIR" && npx wrangler d1 migrations apply DB --env "$env" --remote)
  done
else
  say "Skipped. The deploy workflow applies migrations before each deploy anyway."
fi

say ""
say "Done. Commit wrangler.jsonc (database IDs are identifiers, not secrets)."
