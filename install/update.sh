#!/usr/bin/env bash
# Moves a project to another eng-policies version, as a pull request. Never silently.
#
#   update.sh <project-dir> [--to <tag>] [--apply]
#
# What it does:
#   1. reads .eng-policies.json (what is installed, and the hash of every file it wrote)
#   2. computes what the new version would write, using the same values as the original install
#   3. a file you never touched is updated; a file you changed is NOT touched: the new version is
#      written next to it as <name>.policy-new for you to merge
#   4. with --apply it does this on a new branch `chore/eng-policies-<version>`, commits, pushes and
#      opens a PR (after a typed "yes"). Without --apply it only prints the plan.
#
# --to <tag> defaults to the version of THIS checkout of eng-policies (update the checkout first:
# git -C <eng-policies> pull && git -C <eng-policies> checkout <tag>).
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

DIR=""
APPLY=0
TO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --to) TO="${2:-}"; shift 2 ;;
    -h | --help) sed -n '2,17p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) DIR="$1"; shift ;;
  esac
done
[ -n "$DIR" ] || die "usage: update.sh <project-dir> [--to <tag>] [--apply]"
[ -d "$DIR" ] || die "no such directory: $DIR"
need_node
TARGET="$(cd "$DIR" && pwd)"
RECORD="$TARGET/.eng-policies.json"
[ -f "$RECORD" ] || die "no .eng-policies.json in $TARGET: this project has not adopted eng-policies."

NEW_VERSION="$(policy_version)"
NEW_REF="${TO:-$(default_ref)}"
OLD_VERSION="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' "$RECORD")"
OLD_REF="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).ref)' "$RECORD")"

say "Project:  $TARGET"
say "Installed: $OLD_VERSION (ref $OLD_REF)"
say "Target:    $NEW_VERSION (ref $NEW_REF)"
if [ "$OLD_VERSION" = "$NEW_VERSION" ] && [ "$OLD_REF" = "$NEW_REF" ]; then
  say "Already up to date."
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/engpol-update.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# values from the original install, with the new ref
VALUES="$WORK/values"
node -e '
  const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const v = Object.assign({}, r.values, { POLICY_REF: process.argv[2] });
  for (const [k, val] of Object.entries(v)) console.log(k + "=" + val);
' "$RECORD" "$NEW_REF" >"$VALUES"

# plan: lines "<action>\t<rel>\t<template>"  (update | conflict | same)
PLAN="$WORK/plan"
: >"$PLAN"
FILES="$(node -e '
  const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  for (const f of r.files || []) console.log(f.sha256 + "\t" + f.path + "\t" + f.template);
' "$RECORD")"

while IFS="$(printf '\t')" read -r old_sha rel tpl; do
  [ -n "$rel" ] || continue
  if [ ! -f "$POLICY_ROOT/$tpl" ]; then
    printf 'removed-upstream\t%s\t%s\n' "$rel" "$tpl" >>"$PLAN"
    continue
  fi
  render "$POLICY_ROOT/$tpl" "$VALUES" >"$WORK/new.out"
  new_sha="$(sha "$WORK/new.out")"
  file="$TARGET/$rel"
  if [ ! -f "$file" ]; then
    printf 'missing\t%s\t%s\n' "$rel" "$tpl" >>"$PLAN"
  elif [ "$new_sha" = "$(sha "$file")" ]; then
    printf 'same\t%s\t%s\n' "$rel" "$tpl" >>"$PLAN"
  elif [ "$(sha "$file")" = "$old_sha" ]; then
    printf 'update\t%s\t%s\n' "$rel" "$tpl" >>"$PLAN"
  else
    printf 'conflict\t%s\t%s\n' "$rel" "$tpl" >>"$PLAN"
  fi
done <<EOF
$FILES
EOF

say ""
say "Plan:"
while IFS="$(printf '\t')" read -r action rel _tpl; do
  case "$action" in
    update) info "~ will update:   $rel (you did not change it)" ;;
    conflict) info "! conflict:      $rel (you changed it: new version goes to $rel.policy-new)" ;;
    missing) info "? you deleted:    $rel (left alone)" ;;
    removed-upstream) info "- dropped upstream: $rel (left alone)" ;;
    same) ;;
  esac
done <"$PLAN"
changes="$(grep -c -E '^(update|conflict)' "$PLAN" || true)"
say "$changes file(s) would change. See CHANGELOG.md in eng-policies for what is new."

if [ "$APPLY" -eq 0 ]; then
  say ""
  say "Dry run only. Re-run with --apply to open the PR."
  exit 0
fi

# ---------- apply, on a branch, never on the default branch ----------
command -v git >/dev/null 2>&1 || die "git is required"
command -v gh >/dev/null 2>&1 || die "gh is required to open the PR"
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || die "$TARGET is not a git repository"
[ -z "$(git -C "$TARGET" status --porcelain)" ] || die "the working tree has uncommitted changes. Commit or stash them first."

say ""
printf 'Create branch chore/eng-policies-%s, commit, push and open a PR? Type "yes": ' "$NEW_VERSION"
read -r answer
[ "$answer" = "yes" ] || die "cancelled, nothing was changed."

BRANCH="chore/eng-policies-$NEW_VERSION"
git -C "$TARGET" checkout -b "$BRANCH"

NEWSUMS="$WORK/newsums"
: >"$NEWSUMS"
while IFS="$(printf '\t')" read -r action rel tpl; do
  case "$action" in
    update | same)
      render "$POLICY_ROOT/$tpl" "$VALUES" >"$WORK/new.out"
      if [ "$action" = "update" ]; then cp "$WORK/new.out" "$TARGET/$rel"; fi
      printf '%s\t%s\t%s\n' "$(sha "$WORK/new.out")" "$rel" "$tpl" >>"$NEWSUMS"
      ;;
    conflict)
      render "$POLICY_ROOT/$tpl" "$VALUES" >"$TARGET/$rel.policy-new"
      # keep tracking the file with the hash it had, so the next update still sees your edits
      printf '%s\t%s\t%s\n' "$(sha "$TARGET/$rel")" "$rel" "$tpl" >>"$NEWSUMS"
      ;;
    *)
      old="$(grep -F "$(printf '\t')$rel$(printf '\t')" <<EOF2 | cut -f1
$FILES
EOF2
)"
      printf '%s\t%s\t%s\n' "$old" "$rel" "$tpl" >>"$NEWSUMS"
      ;;
  esac
done <"$PLAN"

NEWSUMS_FILE="$NEWSUMS" RECORD_FILE="$RECORD" NEW_VERSION="$NEW_VERSION" NEW_REF="$NEW_REF" node -e '
  const fs = require("fs");
  const r = JSON.parse(fs.readFileSync(process.env.RECORD_FILE, "utf8"));
  r.version = process.env.NEW_VERSION;
  r.ref = process.env.NEW_REF;
  r.updatedAt = new Date().toISOString();
  r.values.POLICY_REF = process.env.NEW_REF;
  r.files = fs.readFileSync(process.env.NEWSUMS_FILE, "utf8").split("\n").filter(Boolean).map((l) => {
    const [sha256, path, template] = l.split("\t");
    return { path, template, sha256 };
  });
  fs.writeFileSync(process.env.RECORD_FILE, JSON.stringify(r, null, 2) + "\n");
'

git -C "$TARGET" add -A
git -C "$TARGET" commit -q -m "chore: update eng-policies $OLD_VERSION -> $NEW_VERSION"
git -C "$TARGET" push -u origin "$BRANCH"
gh pr create --repo "$(git -C "$TARGET" remote get-url origin | sed -e 's#.*github\.com[:/]##' -e 's#\.git$##')" \
  --head "$BRANCH" \
  --title "chore: update eng-policies to $NEW_VERSION" \
  --body "Updates eng-policies from $OLD_VERSION to $NEW_VERSION.

Files you changed are untouched: the new version is next to them as \`*.policy-new\`. Merge those by hand, then delete the \`.policy-new\` copies.

Check the CI run before merging."
say ""
say "PR opened. Merge it after CI is green and the *.policy-new files are resolved."
