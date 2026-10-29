#!/usr/bin/env bash
# End to end test of the installer and the scripts around it. Used by self-test.yml.
# Everything runs in a temp dir. `gh`, `npx wrangler` (account calls only) are replaced by stubs,
# so no network call to GitHub or Cloudflare is ever made and no credential is needed.
#
#   A. new project in an empty folder: dry run, install, idempotence, then ALL its gates really run
#   B. existing project (the sample app): warn-only mode, nothing overwritten, conflicts listed
#   C. update.sh: untouched file updated, edited file kept as .policy-new, PR opened (stub gh, local remote)
#   D. uninstall: unmodified files removed, edited files kept
#   E. github-setup.sh: dry run changes nothing, --apply sends the right ruleset and environments
#   F. cloudflare-setup.sh: creates D1 + R2 per environment and fills in the IDs
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/engpol-e2e.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1" >&2; }
assert() { # assert <description> <command...>
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}
assert_not() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then bad "$desc"; else ok "$desc"; fi
}
section() { printf '\n== %s\n' "$1"; }

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

OWNER_ARGS=(--policy-owner test-owner --owner test-owner)

# ---------------------------------------------------------------------------------------------
section "A. new project"
NEW="$TMP/new-app"
mkdir -p "$NEW"

bash "$ROOT/install/install.sh" "$NEW" "${OWNER_ARGS[@]}" --name new-app --dry-run >"$TMP/a-dry.txt"
assert "dry run lists the files it would create" grep -q "would create: .github/workflows/ci.yml" "$TMP/a-dry.txt"
assert "dry run lists wrangler.jsonc" grep -q "would create: wrangler.jsonc" "$TMP/a-dry.txt"
assert "dry run lists the record" grep -q "would create: .eng-policies.json" "$TMP/a-dry.txt"
assert "dry run created nothing" test -z "$(ls -A "$NEW")"

bash "$ROOT/install/install.sh" "$NEW" "${OWNER_ARGS[@]}" --name new-app >"$TMP/a-run.txt"
for f in .github/workflows/ci.yml .github/workflows/preview.yml .github/workflows/deploy.yml .github/workflows/codeql.yml \
  .github/workflows/ai-review.yml .github/pull_request_template.md .github/CODEOWNERS .github/dependabot.yml \
  wrangler.jsonc migrations/0000_baseline.sql tests/unit/example.test.ts tests/integration/example.test.ts \
  tests/e2e/smoke.spec.ts docs/prd.md docs/architecture.md docs/adr/0000-record-architecture-decisions.md \
  docs/adoption/PROGRESS.md .gitignore .dev.vars.example CLAUDE.md package.json src/index.ts .eng-policies.json; do
  assert "created $f" test -f "$NEW/$f"
done
assert "no placeholder is left in the caller workflows" bash -c "! grep -rn '__[A-Z_]*__' '$NEW/.github'"
assert "ci caller points at the policy tag" grep -q "test-owner/eng-policies/.github/workflows/ci.yml@v" "$NEW/.github/workflows/ci.yml"
assert "ci caller keeps lint blocking in a new project" grep -q 'lint-mode: "block"' "$NEW/.github/workflows/ci.yml"
assert "wrangler.jsonc uses the app name" grep -q '"name": "new-app-staging"' "$NEW/wrangler.jsonc"
assert ".gitignore ignores .dev.vars" grep -q '^\.dev\.vars$' "$NEW/.gitignore"
assert "record is valid JSON with a version" node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));if(!r.version||!r.files.length)process.exit(1)' "$NEW/.eng-policies.json"

bash "$ROOT/install/install.sh" "$NEW" "${OWNER_ARGS[@]}" --name new-app >"$TMP/a-again.txt"
assert "second run is idempotent (0 created)" grep -q "Summary: 0 file(s) created" "$TMP/a-again.txt"
assert "second run has no conflicts" grep -q "0 conflict(s)" "$TMP/a-again.txt"

echo "  running the real gates of the freshly installed project (npm install, lint, typecheck, tests, build)..."
if (
  cd "$NEW"
  export CI=true NO_D1_WARNING=true
  npm install --no-fund --no-audit >"$TMP/a-npm.log" 2>&1
  npm run --silent lint
  npm run --silent typecheck
  npm run --silent test:unit
  npm run --silent test:integration
  npm run --silent build >/dev/null
) >"$TMP/a-gates.log" 2>&1; then
  ok "new project passes lint, typecheck, unit, integration and build"
else
  bad "new project gates"
  tail -40 "$TMP/a-gates.log" >&2
fi

# ---------------------------------------------------------------------------------------------
section "B. existing project (sample app)"
EXIST="$TMP/existing-app"
mkdir -p "$EXIST"
(cd "$ROOT/examples/sample-app" && tar --exclude=node_modules --exclude=.wrangler --exclude=dist -cf - .) | (cd "$EXIST" && tar -xf -)
(cd "$EXIST" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -q -m init)

BEFORE="$TMP/before.sums"
(cd "$EXIST" && find . -type f -not -path './.git/*' | sort | while IFS= read -r f; do printf '%s  %s\n' "$(sha_of "$f")" "$f"; done) >"$BEFORE"

bash "$ROOT/install/install.sh" "$EXIST" "${OWNER_ARGS[@]}" >"$TMP/b-run.txt"
assert "mode was detected as existing" grep -q "mode=existing" "$TMP/b-run.txt"
assert "lint is warn-only" grep -q 'lint-mode: "warn-only"' "$EXIST/.github/workflows/ci.yml"
assert "typecheck is warn-only" grep -q 'typecheck-mode: "warn-only"' "$EXIST/.github/workflows/ci.yml"
assert "detected the project's own test commands" grep -q 'unit-command: "npm run test:unit"' "$EXIST/.github/workflows/ci.yml"
assert "wrangler.jsonc was NOT overwritten" test "$(sha_of "$EXIST/wrangler.jsonc")" = "$(sha_of "$ROOT/examples/sample-app/wrangler.jsonc")"
assert "conflicting wrangler.jsonc is offered as .policy-new" test -f "$EXIST/wrangler.jsonc.policy-new"
assert "conflicting .gitignore is offered as .policy-new" test -f "$EXIST/.gitignore.policy-new"
assert "the test skeleton was skipped" bash -c "! grep -q 'would create\\|created: tests/' '$TMP/b-run.txt' || ! grep -q 'created: tests/unit/example' '$TMP/b-run.txt'"
assert "no baseline migration was added to a project that has migrations" test ! -f "$EXIST/migrations/0000_baseline.sql.policy-new"
assert "conflicts are listed in the summary" grep -q "Merge these by hand" "$TMP/b-run.txt"
assert "PROGRESS.md records the warn-only gates" grep -q "lint | warn-only" "$EXIST/docs/adoption/PROGRESS.md"

AFTER="$TMP/after.sums"
(cd "$EXIST" && while IFS= read -r line; do f="${line#*  }"; printf '%s  %s\n' "$(sha_of "$f")" "$f"; done <"$BEFORE") >"$AFTER"
assert "every pre-existing file is byte for byte unchanged" diff -q "$BEFORE" "$AFTER"

# ---------------------------------------------------------------------------------------------
section "C. update.sh"
POL="$TMP/policies-copy"
mkdir -p "$POL"
(cd "$ROOT" && tar --exclude=.git --exclude=node_modules --exclude=.wrangler --exclude=dist -cf - .) | (cd "$POL" && tar -xf -)
UPD="$TMP/upd-app"
mkdir -p "$UPD"
bash "$POL/install/install.sh" "$UPD" "${OWNER_ARGS[@]}" --name upd-app >/dev/null
(
  cd "$UPD"
  git init -q -b main
  git config user.name t
  git config user.email t@t
  git add -A
  git commit -q -m "chore: adopt"
  git init -q --bare "$TMP/remote.git"
  git remote add origin "$TMP/remote.git"
  git push -q -u origin main
)

# stub gh: records every call
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
GHLOG="$TMP/gh.log"
: >"$GHLOG"
cat >"$STUBS/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_LOG"
# keep the body of any --input file for inspection
prev=""
for a in "$@"; do
  if [ "$prev" = "--input" ]; then cp "$a" "$GH_STUB_LOG.input.$(printf '%s' "$*" | cksum | cut -d' ' -f1)" 2>/dev/null || true; fi
  prev="$a"
done
case "$*" in
  "auth status"*) exit 0 ;;
  "api repos/test-owner/proj --jq .private") echo "false" ;;
  "api repos/test-owner/proj/rulesets --jq"*) : ;;
  "api users/test-owner --jq .id") echo "12345" ;;
esac
exit 0
EOF
chmod +x "$STUBS/gh"

# simulate a new policy version: the PR template changes upstream, CODEOWNERS changes upstream
printf '1.0.0-alpha.2\n' >"$POL/VERSION"
printf '\n## Extra section added in alpha.2\n' >>"$POL/templates/.github/pull_request_template.md"
printf '\n# added upstream in alpha.2\n' >>"$POL/templates/.github/CODEOWNERS"
# the user edited CODEOWNERS in the project, so it must be kept
printf '\n# my own rule\n' >>"$UPD/.github/CODEOWNERS"
(cd "$UPD" && git add -A && git -c user.name=t -c user.email=t@t commit -q -m "chore: edit CODEOWNERS")

REMOTE_MAIN_BEFORE="$(git -C "$TMP/remote.git" rev-parse main)"
PATH="$STUBS:$PATH" GH_STUB_LOG="$GHLOG" bash "$POL/install/update.sh" "$UPD" >"$TMP/c-plan.txt"
assert "dry run plans an update of the untouched file" grep -q "will update:   .github/pull_request_template.md" "$TMP/c-plan.txt"
assert "dry run plans a conflict for the edited file" grep -q "conflict:      .github/CODEOWNERS" "$TMP/c-plan.txt"
assert "dry run changed nothing" test -z "$(cd "$UPD" && git status --porcelain)"

printf 'yes\n' | PATH="$STUBS:$PATH" GH_STUB_LOG="$GHLOG" bash "$POL/install/update.sh" "$UPD" --apply >"$TMP/c-apply.txt" 2>&1 || {
  bad "update --apply failed"
  cat "$TMP/c-apply.txt" >&2
}
assert "update used a new branch, not main" test "$(git -C "$UPD" rev-parse --abbrev-ref HEAD)" = "chore/eng-policies-1.0.0-alpha.2"
assert "untouched file was updated" grep -q "Extra section added in alpha.2" "$UPD/.github/pull_request_template.md"
assert "edited file was NOT overwritten" grep -q "my own rule" "$UPD/.github/CODEOWNERS"
assert "edited file got a .policy-new copy" grep -q "added upstream in alpha.2" "$UPD/.github/CODEOWNERS.policy-new"
assert "record shows the new version" grep -q '"version": "1.0.0-alpha.2"' "$UPD/.eng-policies.json"
assert "caller workflows point at the new tag" grep -q "@v1.0.0-alpha.2" "$UPD/.github/workflows/ci.yml"
assert "branch was pushed" git -C "$TMP/remote.git" rev-parse --verify "chore/eng-policies-1.0.0-alpha.2"
assert "a PR was requested" grep -q "^pr create" "$GHLOG"
assert "main on the remote was not touched" test "$(git -C "$TMP/remote.git" rev-parse main)" = "$REMOTE_MAIN_BEFORE"

# ---------------------------------------------------------------------------------------------
section "D. uninstall"
printf '\n# edited by me\n' >>"$NEW/CLAUDE.md"
bash "$ROOT/install/install.sh" --uninstall "$NEW" --dry-run >"$TMP/d-dry.txt"
assert "uninstall dry run keeps everything" test -f "$NEW/.github/workflows/ci.yml"
bash "$ROOT/install/install.sh" --uninstall "$NEW" >"$TMP/d-run.txt"
assert "unmodified file removed" test ! -f "$NEW/.github/workflows/ci.yml"
assert "edited file kept" test -f "$NEW/CLAUDE.md"
assert "edited file is reported" grep -q "kept (you changed it): CLAUDE.md" "$TMP/d-run.txt"
assert "record removed" test ! -f "$NEW/.eng-policies.json"

# ---------------------------------------------------------------------------------------------
section "E. github-setup.sh"
: >"$GHLOG"
PATH="$STUBS:$PATH" GH_STUB_LOG="$GHLOG" bash "$ROOT/install/github-setup.sh" test-owner/proj >"$TMP/e-dry.txt"
assert "dry run prints the plan" grep -q "ci / gate" "$TMP/e-dry.txt"
assert "dry run prints the gh secret set commands" grep -q "gh secret set CLOUDFLARE_API_TOKEN" "$TMP/e-dry.txt"
assert "dry run made no gh call" test ! -s "$GHLOG"

printf 'yes\n' | PATH="$STUBS:$PATH" GH_STUB_LOG="$GHLOG" bash "$ROOT/install/github-setup.sh" test-owner/proj --apply >"$TMP/e-apply.txt" 2>&1 || {
  bad "github-setup --apply failed"
  cat "$TMP/e-apply.txt" >&2
}
assert "created the ruleset" grep -q "api --method POST repos/test-owner/proj/rulesets" "$GHLOG"
assert "created the staging environment" grep -q "api --method PUT repos/test-owner/proj/environments/staging" "$GHLOG"
assert "created the production environment" grep -q "api --method PUT repos/test-owner/proj/environments/production" "$GHLOG"
RS_FILE="$(grep -l '"type": "required_status_checks"' "$GHLOG".input.* | head -1)"
assert "ruleset body is valid JSON requiring ci / gate, no force-push, a PR" node -e '
  const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const types = r.rules.map((x) => x.type);
  const rsc = r.rules.find((x) => x.type === "required_status_checks");
  const ok = types.includes("non_fast_forward") && types.includes("pull_request") && types.includes("deletion")
    && rsc.parameters.required_status_checks[0].context === "ci / gate"
    && r.conditions.ref_name.include[0] === "refs/heads/main" && r.enforcement === "active";
  process.exit(ok ? 0 : 1);
' "$RS_FILE"
ENV_FILE="$(grep -l '"reviewers"' "$GHLOG".input.* | head -1)"
assert "production environment requires the reviewer" node -e '
  const e = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  process.exit(e.reviewers[0].id === 12345 && e.reviewers[0].type === "User" ? 0 : 1);
' "$ENV_FILE"
assert "no secret value was printed" bash -c "! grep -qiE 'ghp_|github_pat_|sk-ant' '$TMP/e-apply.txt'"

if printf 'no\n' | PATH="$STUBS:$PATH" GH_STUB_LOG="$GHLOG" bash "$ROOT/install/github-setup.sh" test-owner/proj --apply >/dev/null 2>&1; then
  bad "answering no must cancel"
else
  ok "answering no cancels"
fi

# ---------------------------------------------------------------------------------------------
section "F. cloudflare-setup.sh"
CF="$TMP/cf-app"
mkdir -p "$CF"
bash "$ROOT/install/install.sh" "$CF" "${OWNER_ARGS[@]}" --name cf-app >/dev/null
bash "$ROOT/install/cloudflare-setup.sh" "$CF" >"$TMP/f-dry.txt"
assert "dry run prints d1 create for each environment" bash -c "grep -q 'wrangler d1 create cf-app-preview-db' '$TMP/f-dry.txt' && grep -q 'wrangler d1 create cf-app-production-db' '$TMP/f-dry.txt'"
assert "dry run printed r2 commands" grep -q "wrangler r2 bucket create cf-app-staging-files" "$TMP/f-dry.txt"
assert "dry run left the placeholders" grep -q "00000000-0000-0000-0000-000000000001" "$CF/wrangler.jsonc"

NPXLOG="$TMP/npx.log"
: >"$NPXLOG"
cat >"$STUBS/npx" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NPX_STUB_LOG"
case "$*" in
  "wrangler whoami"*) exit 0 ;;
  "wrangler d1 info"*) exit 1 ;;
  "wrangler d1 create"*)
    case "$*" in
      *preview*) echo "database_id = \"11111111-1111-1111-1111-111111111111\"" ;;
      *staging*) echo "database_id = \"22222222-2222-2222-2222-222222222222\"" ;;
      *production*) echo "database_id = \"33333333-3333-3333-3333-333333333333\"" ;;
    esac
    exit 0
    ;;
  "wrangler r2 bucket list"*) exit 0 ;;
esac
exit 0
EOF
chmod +x "$STUBS/npx"
printf 'yes\nno\n' | PATH="$STUBS:$PATH" NPX_STUB_LOG="$NPXLOG" bash "$ROOT/install/cloudflare-setup.sh" "$CF" --apply >"$TMP/f-apply.txt" 2>&1 || {
  bad "cloudflare-setup --apply failed"
  cat "$TMP/f-apply.txt" >&2
}
assert "preview database id filled in" grep -q "11111111-1111-1111-1111-111111111111" "$CF/wrangler.jsonc"
assert "staging database id filled in" grep -q "22222222-2222-2222-2222-222222222222" "$CF/wrangler.jsonc"
assert "production database id filled in" grep -q "33333333-3333-3333-3333-333333333333" "$CF/wrangler.jsonc"
assert "no placeholder id is left" bash -c "! grep -q '00000000-0000-0000-0000-00000000000' '$CF/wrangler.jsonc'"
assert "created one bucket per environment" bash -c "[ \"\$(grep -c 'r2 bucket create' '$NPXLOG')\" = 3 ]"
assert "wrangler.jsonc is still valid JSONC" node -e '
  const t = require("fs").readFileSync(process.argv[1], "utf8").replace(/^\s*\/\/.*$/gm, "");
  JSON.parse(t);
' "$CF/wrangler.jsonc"

# ---------------------------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
