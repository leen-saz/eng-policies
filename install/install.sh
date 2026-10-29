#!/usr/bin/env bash
# eng-policies installer.
#
#   install.sh <target-dir> [--mode new|existing] [--dry-run] [options]
#   install.sh --global [--dry-run]            install ~/.claude/CLAUDE.md and the skills
#   install.sh --uninstall <target-dir> [--dry-run]
#
# Rules this script follows:
#   - It never overwrites a file. A file that already exists and differs is written next to it as
#     <name>.policy-new and listed at the end, for you to merge by hand.
#   - It never prints or writes a secret value.
#   - --dry-run changes nothing and lists every file it would create.
#
# Options:
#   --mode new|existing     default: "existing" when the target already has a package.json, else "new".
#                           "existing" sets lint and typecheck to warn-only in CI (brownfield adoption).
#   --name <app>            app name used in wrangler.jsonc (default: package.json name or folder name)
#   --owner <github-handle> CODEOWNERS owner (default: owner of the target's origin remote)
#   --policy-owner <owner>  GitHub owner of eng-policies (default: owner of this repo's origin remote)
#   --ref <tag>             policy tag that caller workflows point at (default: the current version tag)
#   --pm npm|pnpm|yarn      force the package manager instead of detecting it
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

MODE=""
DRY=0
GLOBAL=0
UNINSTALL=0
TARGET=""
APP_NAME=""
OWNER_HANDLE=""
POLICY_OWNER=""
POLICY_REF=""
PM_FORCED=""

usage() {
  sed -n '2,24p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --global) GLOBAL=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --name) APP_NAME="${2:-}"; shift 2 ;;
    --owner) OWNER_HANDLE="${2:-}"; shift 2 ;;
    --policy-owner) POLICY_OWNER="${2:-}"; shift 2 ;;
    --ref) POLICY_REF="${2:-}"; shift 2 ;;
    --pm) PM_FORCED="${2:-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *)
      [ -z "$TARGET" ] || die "only one target directory is allowed"
      TARGET="$1"
      shift
      ;;
  esac
done

need_node

# what the user passed explicitly always wins over anything recorded earlier
CLI_MODE="$MODE"
CLI_APP_NAME="$APP_NAME"
CLI_OWNER_HANDLE="$OWNER_HANDLE"
CLI_POLICY_OWNER="$POLICY_OWNER"
CLI_POLICY_REF="$POLICY_REF"

# ---------------------------------------------------------------------------------------------
# --global: ~/.claude/CLAUDE.md and ~/.claude/skills/*  (never overwrites)
# ---------------------------------------------------------------------------------------------
copy_noclobber() { # copy_noclobber <src> <dest>
  local src="$1" dest="$2"
  if [ ! -e "$dest" ]; then
    if [ "$DRY" -eq 1 ]; then
      info "+ would create: $dest"
    else
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
      info "+ created: $dest"
    fi
  elif [ "$(sha "$src")" = "$(sha "$dest")" ]; then
    info "= unchanged: $dest"
  else
    if [ "$DRY" -eq 1 ]; then
      info "~ would write conflict copy: $dest.policy-new"
    else
      cp "$src" "$dest.policy-new"
      info "~ conflict, wrote: $dest.policy-new (merge it by hand, then delete it)"
    fi
  fi
}

if [ "$GLOBAL" -eq 1 ]; then
  say "eng-policies $(policy_version): global install$([ "$DRY" -eq 1 ] && printf ' (dry run)')"
  home_claude="${HOME}/.claude"
  copy_noclobber "$POLICY_ROOT/claude/CLAUDE.global.md" "$home_claude/CLAUDE.md"
  for skill_dir in "$POLICY_ROOT"/skills/*/; do
    name="$(basename "$skill_dir")"
    copy_noclobber "$skill_dir/SKILL.md" "$home_claude/skills/$name/SKILL.md"
  done
  say ""
  say "Prefer the plugin? In Claude Code run:"
  say "  /plugin marketplace add <owner>/eng-policies"
  say "  /plugin install eng-policies@eng-policies"
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# everything below needs a target directory
# ---------------------------------------------------------------------------------------------
[ -n "$TARGET" ] || { usage; exit 1; }

if [ ! -d "$TARGET" ]; then
  if [ "$DRY" -eq 1 ]; then
    TARGET_ABS="$TARGET"
  else
    mkdir -p "$TARGET"
    TARGET_ABS="$(cd "$TARGET" && pwd)"
  fi
else
  TARGET_ABS="$(cd "$TARGET" && pwd)"
fi

RECORD="$TARGET_ABS/.eng-policies.json"

# ---------------------------------------------------------------------------------------------
# --uninstall: remove only files that are still exactly what the installer wrote
# ---------------------------------------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
  [ -f "$RECORD" ] || die "no .eng-policies.json in $TARGET_ABS: nothing to uninstall."
  say "eng-policies: uninstall from $TARGET_ABS$([ "$DRY" -eq 1 ] && printf ' (dry run)')"
  list="$(node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    for (const f of r.files || []) console.log(f.sha256 + "  " + f.path);
  ' "$RECORD")"
  kept=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    want="${line%%  *}"
    rel="${line#*  }"
    file="$TARGET_ABS/$rel"
    if [ ! -f "$file" ]; then
      continue
    fi
    if [ "$(sha "$file")" = "$want" ]; then
      if [ "$DRY" -eq 1 ]; then
        info "- would remove: $rel"
      else
        rm -f "$file"
        rmdir -p "$(dirname "$file")" 2>/dev/null || true
        info "- removed: $rel"
      fi
    else
      kept=$((kept + 1))
      info "! kept (you changed it): $rel"
    fi
  done <<EOF
$list
EOF
  # leftovers of conflicts
  while IFS= read -r pn; do
    [ -n "$pn" ] || continue
    if [ "$DRY" -eq 1 ]; then
      info "- would remove: ${pn#"$TARGET_ABS"/}"
    else
      rm -f "$pn"
      info "- removed: ${pn#"$TARGET_ABS"/}"
    fi
  done <<EOF
$(find "$TARGET_ABS" -name '*.policy-new' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)
EOF
  if [ "$DRY" -eq 0 ]; then
    rm -f "$RECORD"
    info "- removed: .eng-policies.json"
  fi
  say ""
  say "Done. $kept file(s) were kept because you changed them. Review them by hand."
  say "Not touched: GitHub rulesets and environments, Cloudflare resources, secrets, and ~/.claude."
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# detection
# ---------------------------------------------------------------------------------------------
PKG="$TARGET_ABS/package.json"
HAS_PKG=0
[ -f "$PKG" ] && HAS_PKG=1

# A re-run on a project that already has a record reuses the recorded mode, so it stays idempotent
# (after the first install a "new" project has a package.json and would otherwise look "existing").
if [ -z "$MODE" ] && [ -f "$RECORD" ]; then
  MODE="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).mode || "")' "$RECORD")"
fi
if [ -z "$MODE" ]; then
  if [ "$HAS_PKG" -eq 1 ]; then MODE="existing"; else MODE="new"; fi
fi
case "$MODE" in new | existing) ;; *) die "--mode must be new or existing" ;; esac

# package manager
PM="npm"
YARN_BERRY=0
if [ -n "$PM_FORCED" ]; then
  PM="$PM_FORCED"
elif [ -f "$TARGET_ABS/pnpm-lock.yaml" ]; then
  PM="pnpm"
elif [ -f "$TARGET_ABS/yarn.lock" ]; then
  PM="yarn"
elif [ -f "$TARGET_ABS/package-lock.json" ]; then
  PM="npm"
elif [ -f "$TARGET_ABS/bun.lockb" ] || [ -f "$TARGET_ABS/bun.lock" ]; then
  warn "bun detected: the shared CI uses npm, pnpm or yarn. Falling back to npm commands."
elif [ "$HAS_PKG" -eq 1 ]; then
  declared="$(pkg_field "$PKG" packageManager || true)"
  case "$declared" in pnpm@*) PM="pnpm" ;; yarn@*) PM="yarn" ;; esac
fi
case "$PM" in npm | pnpm | yarn) ;; *) die "--pm must be npm, pnpm or yarn" ;; esac
[ -f "$TARGET_ABS/.yarnrc.yml" ] && YARN_BERRY=1

# commands
if [ "$MODE" = "new" ] && [ "$HAS_PKG" -eq 0 ]; then
  # the new-project starter defines these scripts
  HAS_LINT=1; HAS_TYPECHECK=1; HAS_UNIT=1; HAS_INTEGRATION=1; HAS_BUILD=1; HAS_E2E=1
  LANGUAGE="typescript"
  RUNNER="vitest"
else
  HAS_LINT=0; HAS_TYPECHECK=0; HAS_UNIT=0; HAS_INTEGRATION=0; HAS_BUILD=0; HAS_E2E=0
  LANGUAGE="javascript"
  RUNNER="none"
  if [ "$HAS_PKG" -eq 1 ]; then
    pkg_script "$PKG" lint && HAS_LINT=1
    pkg_script "$PKG" typecheck && HAS_TYPECHECK=1
    pkg_script "$PKG" test:unit && HAS_UNIT=1
    pkg_script "$PKG" test:integration && HAS_INTEGRATION=1
    pkg_script "$PKG" build && HAS_BUILD=1
    pkg_script "$PKG" test:e2e && HAS_E2E=1
    for r in vitest jest mocha ava; do
      if pkg_dep "$PKG" "$r"; then RUNNER="$r"; break; fi
    done
    if [ "$HAS_UNIT" -eq 0 ] && pkg_script "$PKG" test; then HAS_UNIT=2; fi
  fi
  if [ -f "$TARGET_ABS/tsconfig.json" ] || { [ "$HAS_PKG" -eq 1 ] && pkg_dep "$PKG" typescript; }; then
    LANGUAGE="typescript"
  fi
fi

run_cmd() { # run_cmd <script>
  case "$PM" in
    npm) printf 'npm run %s' "$1" ;;
    pnpm) printf 'pnpm run %s' "$1" ;;
    yarn) printf 'yarn run %s' "$1" ;;
  esac
}

case "$PM" in
  npm)
    if [ -f "$TARGET_ABS/package-lock.json" ]; then
      INSTALL_CMD="npm ci"
    else
      # No lockfile yet (a brand new project): install creates it. Once it is committed, npm ci takes over.
      INSTALL_CMD="if [ -f package-lock.json ]; then npm ci; else npm install; fi"
    fi
    AUDIT_CMD="npm audit --audit-level=high"
    ;;
  pnpm)
    INSTALL_CMD="pnpm install --frozen-lockfile"
    AUDIT_CMD="pnpm audit --audit-level high"
    ;;
  yarn)
    if [ "$YARN_BERRY" -eq 1 ]; then
      INSTALL_CMD="yarn install --immutable"
      AUDIT_CMD="yarn npm audit --severity high"
    else
      INSTALL_CMD="yarn install --frozen-lockfile"
      AUDIT_CMD="yarn audit --level high"
    fi
    ;;
esac

LINT_CMD=""; TYPECHECK_CMD=""; UNIT_CMD=""; INTEGRATION_CMD=""; BUILD_CMD=""
[ "$HAS_LINT" -ge 1 ] && LINT_CMD="$(run_cmd lint)"
if [ "$HAS_TYPECHECK" -ge 1 ]; then
  TYPECHECK_CMD="$(run_cmd typecheck)"
elif [ -f "$TARGET_ABS/tsconfig.json" ]; then
  TYPECHECK_CMD="npx tsc --noEmit"
fi
if [ "$HAS_UNIT" -eq 1 ]; then
  UNIT_CMD="$(run_cmd test:unit)"
elif [ "$HAS_UNIT" -eq 2 ]; then
  UNIT_CMD="$(run_cmd test)"
fi
[ "$HAS_INTEGRATION" -ge 1 ] && INTEGRATION_CMD="$(run_cmd test:integration)"
[ "$HAS_BUILD" -ge 1 ] && BUILD_CMD="$(run_cmd build)"
if [ "$HAS_E2E" -ge 1 ]; then E2E_CMD="$(run_cmd test:e2e)"; else E2E_CMD="npx playwright test"; fi

DEV_CMD="$(run_cmd dev)"
MIGRATE_LOCAL_CMD="npx wrangler d1 migrations apply DB --env staging --local"

if [ "$MODE" = "existing" ]; then
  LINT_MODE="warn-only"
  TYPECHECK_MODE="warn-only"
else
  LINT_MODE="block"
  TYPECHECK_MODE="block"
fi

# names and owners
if [ -z "$APP_NAME" ]; then
  if [ "$HAS_PKG" -eq 1 ]; then APP_NAME="$(pkg_field "$PKG" name || true)"; fi
  [ -n "$APP_NAME" ] || APP_NAME="$(basename "$TARGET_ABS")"
fi
APP_NAME="$(slugify "$APP_NAME")"
[ -n "$APP_NAME" ] || APP_NAME="my-app"

if [ -z "$POLICY_OWNER" ]; then POLICY_OWNER="$(github_owner_of "$POLICY_ROOT")"; fi
if [ -z "$POLICY_OWNER" ]; then POLICY_OWNER="${ENG_POLICIES_OWNER:-}"; fi
if [ -z "$POLICY_OWNER" ]; then
  POLICY_OWNER="OWNER"
  warn "could not detect the GitHub owner of eng-policies. Re-run with --policy-owner <owner>, or edit the 'uses:' lines in .github/workflows/."
fi
if [ -z "$OWNER_HANDLE" ]; then OWNER_HANDLE="$(github_owner_of "$TARGET_ABS")"; fi
if [ -z "$OWNER_HANDLE" ]; then OWNER_HANDLE="$POLICY_OWNER"; fi
[ -n "$POLICY_REF" ] || POLICY_REF="$(default_ref)"

# ---------------------------------------------------------------------------------------------
# values used by templates
# ---------------------------------------------------------------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/engpol.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
VALUES="$WORK/values"
{
  printf 'APP_NAME=%s\n' "$APP_NAME"
  printf 'PROJECT_NAME=%s\n' "$APP_NAME"
  printf 'POLICY_OWNER=%s\n' "$POLICY_OWNER"
  printf 'POLICY_REF=%s\n' "$POLICY_REF"
  printf 'OWNER_HANDLE=%s\n' "$OWNER_HANDLE"
  printf 'COMPAT_DATE=%s\n' "$(compat_date)"
  printf 'DATE=%s\n' "$(today)"
  printf 'MODE=%s\n' "$MODE"
  printf 'PACKAGE_MANAGER=%s\n' "$PM"
  printf 'INSTALL_CMD=%s\n' "$INSTALL_CMD"
  printf 'LINT_CMD=%s\n' "$LINT_CMD"
  printf 'LINT_MODE=%s\n' "$LINT_MODE"
  printf 'TYPECHECK_CMD=%s\n' "$TYPECHECK_CMD"
  printf 'TYPECHECK_MODE=%s\n' "$TYPECHECK_MODE"
  printf 'UNIT_CMD=%s\n' "$UNIT_CMD"
  printf 'INTEGRATION_CMD=%s\n' "$INTEGRATION_CMD"
  printf 'BUILD_CMD=%s\n' "$BUILD_CMD"
  printf 'AUDIT_CMD=%s\n' "$AUDIT_CMD"
  printf 'E2E_CMD=%s\n' "$E2E_CMD"
  printf 'DEV_CMD=%s\n' "$DEV_CMD"
  printf 'MIGRATE_LOCAL_CMD=%s\n' "$MIGRATE_LOCAL_CMD"
} >"$VALUES"

# Re-run: keep every recorded value (commands, dates, modes) except what was passed explicitly now.
# Otherwise a new day, or a lockfile that appeared, would turn unchanged files into conflicts.
if [ -f "$RECORD" ]; then
  EXCLUDE=""
  [ -n "$CLI_APP_NAME" ] && EXCLUDE="$EXCLUDE APP_NAME PROJECT_NAME"
  [ -n "$CLI_OWNER_HANDLE" ] && EXCLUDE="$EXCLUDE OWNER_HANDLE"
  [ -n "$CLI_POLICY_OWNER" ] && EXCLUDE="$EXCLUDE POLICY_OWNER"
  [ -n "$CLI_POLICY_REF" ] && EXCLUDE="$EXCLUDE POLICY_REF"
  [ -n "$CLI_MODE" ] && EXCLUDE="$EXCLUDE MODE LINT_MODE TYPECHECK_MODE"
  EXCLUDE_KEYS="$EXCLUDE" VALUES_FILE="$VALUES" RECORD_FILE="$RECORD" node -e '
    const fs = require("fs");
    const skip = new Set((process.env.EXCLUDE_KEYS || "").split(/\s+/).filter(Boolean));
    const cur = {};
    for (const l of fs.readFileSync(process.env.VALUES_FILE, "utf8").split("\n").filter(Boolean)) {
      const i = l.indexOf("=");
      cur[l.slice(0, i)] = l.slice(i + 1);
    }
    let rec = {};
    try { rec = JSON.parse(fs.readFileSync(process.env.RECORD_FILE, "utf8")).values || {}; } catch (e) { /* unreadable record: keep detection */ }
    for (const [k, v] of Object.entries(rec)) if (!skip.has(k)) cur[k] = v;
    fs.writeFileSync(process.env.VALUES_FILE, Object.entries(cur).map(([k, v]) => k + "=" + v).join("\n") + "\n");
  '
  POLICY_REF="$(grep '^POLICY_REF=' "$VALUES" | cut -d= -f2-)"
fi

# ---------------------------------------------------------------------------------------------
# file placement
# ---------------------------------------------------------------------------------------------
MANIFEST="$WORK/manifest"   # lines: <sha256>\t<dest-rel>\t<template-rel>
CONFLICTS="$WORK/conflicts" # lines: <dest-rel>
CREATED="$WORK/created"
: >"$MANIFEST"
: >"$CONFLICTS"
: >"$CREATED"
UNCHANGED_COUNT=0

# place <template-path-relative-to-policy-root> <dest-relative-to-target> [force-conflict-name]
place() {
  local tpl="$1" rel="$2" conflict_rel="${3:-}"
  local dest="$TARGET_ABS/$rel" out sum
  out="$WORK/out.$$"
  render "$POLICY_ROOT/$tpl" "$VALUES" >"$out"
  sum="$(sha "$out")"

  if [ -n "$conflict_rel" ]; then
    # another config of the same kind already exists: always a conflict copy
    printf '%s\n' "$conflict_rel" >>"$CONFLICTS"
    if [ "$DRY" -eq 1 ]; then
      info "~ would write conflict copy: $conflict_rel"
    else
      mkdir -p "$(dirname "$TARGET_ABS/$conflict_rel")"
      cp "$out" "$TARGET_ABS/$conflict_rel"
      info "~ conflict, wrote: $conflict_rel"
    fi
    return
  fi

  if [ ! -e "$dest" ]; then
    printf '%s\t%s\t%s\n' "$sum" "$rel" "$tpl" >>"$MANIFEST"
    printf '%s\n' "$rel" >>"$CREATED"
    if [ "$DRY" -eq 1 ]; then
      info "+ would create: $rel"
    else
      mkdir -p "$(dirname "$dest")"
      cp "$out" "$dest"
      info "+ created: $rel"
    fi
  elif [ "$(sha "$dest")" = "$sum" ]; then
    printf '%s\t%s\t%s\n' "$sum" "$rel" "$tpl" >>"$MANIFEST"
    UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
    info "= unchanged: $rel"
  else
    printf '%s.policy-new\n' "$rel" >>"$CONFLICTS"
    if [ "$DRY" -eq 1 ]; then
      info "~ would write conflict copy: $rel.policy-new"
    else
      cp "$out" "$dest.policy-new"
      info "~ conflict, wrote: $rel.policy-new"
    fi
  fi
  rm -f "$out"
}

say "eng-policies $(policy_version): installing into $TARGET_ABS$([ "$DRY" -eq 1 ] && printf ' (dry run)')"
say "mode=$MODE  package-manager=$PM  language=$LANGUAGE  test-runner=$RUNNER  ref=$POLICY_REF"
if [ "$MODE" = "existing" ]; then
  say "lint and typecheck are warn-only in CI (existing project). See docs/adoption/PROGRESS.md."
fi
say ""

# -- core files (every project) --
say "Workflows and GitHub files:"
for wf in ci preview deploy codeql ai-review; do
  place "templates/workflows/$wf.yml" ".github/workflows/$wf.yml"
done
place "templates/.github/pull_request_template.md" ".github/pull_request_template.md"
place "templates/.github/CODEOWNERS" ".github/CODEOWNERS"
place "templates/.github/dependabot.yml" ".github/dependabot.yml"

say "Project files:"
place "templates/.gitignore" ".gitignore"
place "templates/.dev.vars.example" ".dev.vars.example"
place "claude/CLAUDE.project.md" "CLAUDE.md"

# wrangler: a project must have exactly one config file
existing_wrangler=""
for f in wrangler.jsonc wrangler.json wrangler.toml; do
  if [ -f "$TARGET_ABS/$f" ]; then existing_wrangler="$f"; break; fi
done
if [ -z "$existing_wrangler" ]; then
  place "templates/wrangler.jsonc" "wrangler.jsonc"
elif [ "$existing_wrangler" = "wrangler.jsonc" ]; then
  place "templates/wrangler.jsonc" "wrangler.jsonc"
else
  place "templates/wrangler.jsonc" "wrangler.jsonc" "wrangler.jsonc.policy-new"
  warn "$existing_wrangler already exists. The template was written as wrangler.jsonc.policy-new: copy its env.preview / env.staging / env.production blocks (own D1 + R2 each) into your config."
fi

say "BMAD docs:"
place "templates/docs/prd.md" "docs/prd.md"
place "templates/docs/architecture.md" "docs/architecture.md"
place "templates/docs/stories/README.md" "docs/stories/README.md"
place "templates/docs/adr/0000-record-architecture-decisions.md" "docs/adr/0000-record-architecture-decisions.md"
place "templates/docs/adoption/PROGRESS.md" "docs/adoption/PROGRESS.md"

# -- skeleton: only when it will not collide with what an existing project already has --
SKELETON=1
if [ "$MODE" = "existing" ] && { [ -d "$TARGET_ABS/tests" ] || [ -d "$TARGET_ABS/test" ] || [ "$RUNNER" != "none" ]; }; then
  SKELETON=0
fi
HAS_MIGRATIONS=0
if [ -d "$TARGET_ABS/migrations" ] && [ -n "$(find "$TARGET_ABS/migrations" -maxdepth 1 -name '*.sql' 2>/dev/null | head -1)" ]; then
  HAS_MIGRATIONS=1
fi

say "Database:"
if [ "$HAS_MIGRATIONS" -eq 1 ]; then
  info "- skipped migrations/0000_baseline.sql: this project already has migrations"
else
  place "templates/migrations/0000_baseline.sql" "migrations/0000_baseline.sql"
fi

say "Test skeleton:"
if [ "$SKELETON" -eq 1 ]; then
  place "templates/tests/unit/example.test.ts" "tests/unit/example.test.ts"
  place "templates/tests/integration/example.test.ts" "tests/integration/example.test.ts"
  place "templates/tests/e2e/smoke.spec.ts" "tests/e2e/smoke.spec.ts"
  place "templates/vitest.config.ts" "vitest.config.ts"
  place "templates/vitest.integration.config.ts" "vitest.integration.config.ts"
  place "templates/playwright.config.ts" "playwright.config.ts"
else
  info "- skipped: this project already has tests or a test runner ($RUNNER). Add integration and E2E tests as stories."
fi

# -- starter app (new projects only) --
if [ "$MODE" = "new" ]; then
  say "Starter app:"
  place "templates/new-project/package.json" "package.json"
  place "templates/new-project/tsconfig.json" "tsconfig.json"
  place "templates/new-project/eslint.config.js" "eslint.config.js"
  place "templates/new-project/src/index.ts" "src/index.ts"
fi

# ---------------------------------------------------------------------------------------------
# record
# ---------------------------------------------------------------------------------------------
if [ "$DRY" -eq 0 ]; then
  MANIFEST_FILE="$MANIFEST" CONFLICTS_FILE="$CONFLICTS" VALUES_FILE="$VALUES" RECORD_FILE="$RECORD" \
    POLICY_VERSION="$(policy_version)" POLICY_REF_V="$POLICY_REF" POLICY_OWNER_V="$POLICY_OWNER" MODE_V="$MODE" \
    node -e '
      const fs = require("fs");
      const lines = (p) => fs.readFileSync(p, "utf8").split("\n").filter(Boolean);
      const values = {};
      for (const l of lines(process.env.VALUES_FILE)) {
        const i = l.indexOf("=");
        values[l.slice(0, i)] = l.slice(i + 1);
      }
      const files = lines(process.env.MANIFEST_FILE).map((l) => {
        const [sha256, path, template] = l.split("\t");
        return { path, template, sha256 };
      });
      let previous = {};
      try { previous = JSON.parse(fs.readFileSync(process.env.RECORD_FILE, "utf8")); } catch (e) { /* first install */ }
      // files from an earlier run stay tracked unless this run re-evaluated them
      const seen = new Set(files.map((f) => f.path));
      for (const f of previous.files || []) if (!seen.has(f.path)) files.push(f);
      const now = new Date().toISOString();
      const record = {
        name: "eng-policies",
        version: process.env.POLICY_VERSION,
        ref: process.env.POLICY_REF_V,
        source: process.env.POLICY_OWNER_V + "/eng-policies",
        mode: process.env.MODE_V,
        installedAt: previous.installedAt || now,
        updatedAt: now,
        values,
        files,
        conflicts: lines(process.env.CONFLICTS_FILE),
      };
      fs.writeFileSync(process.env.RECORD_FILE, JSON.stringify(record, null, 2) + "\n");
    '
  info "+ recorded: .eng-policies.json (version $(policy_version))"
else
  info "+ would create: .eng-policies.json"
fi

# ---------------------------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------------------------
say ""
created_n="$(wc -l <"$CREATED" | tr -d ' ')"
conflict_n="$(wc -l <"$CONFLICTS" | tr -d ' ')"
say "Summary: $created_n file(s) $([ "$DRY" -eq 1 ] && printf 'would be ')created, $UNCHANGED_COUNT unchanged, $conflict_n conflict(s)."
if [ "$conflict_n" -gt 0 ]; then
  say ""
  say "Merge these by hand (the installer never overwrites), then delete the .policy-new copies:"
  while IFS= read -r c; do info "$c"; done <"$CONFLICTS"
fi

if [ "$DRY" -eq 0 ]; then
  say ""
  say "Next steps:"
  info "1. git checkout -b chore/adopt-eng-policies && git add -A && git commit -m 'chore: adopt eng-policies'"
  info "2. install/github-setup.sh <owner/repo>      (ruleset, environments, list of secrets)"
  info "3. install/cloudflare-setup.sh <target-dir>  (D1 + R2 per environment, fills wrangler.jsonc)"
  info "4. In the policies repo, allow other repos to call its workflows (Settings > Actions > Access) if it is private."
fi
