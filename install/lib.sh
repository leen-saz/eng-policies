#!/usr/bin/env bash
# Shared helpers for the eng-policies scripts. Sourced, never executed.
# Written for bash 3.2 (the macOS default): no associative arrays, no mapfile, no sed -i.

# ---------- output ----------
say() { printf '%s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# ---------- paths ----------
# Resolves the directory of the calling script without readlink -f (not on macOS).
script_dir() {
  (cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)
}

POLICY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export POLICY_ROOT

policy_version() {
  tr -d '[:space:]' <"$POLICY_ROOT/VERSION"
}

# A prerelease (contains "-") is pinned by its exact tag. A stable release follows the moving major tag.
default_ref() {
  local v
  v="$(policy_version)"
  case "$v" in
    *-*) printf 'v%s' "$v" ;;
    *) printf 'v%s' "${v%%.*}" ;;
  esac
}

# ---------- hashing ----------
sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# ---------- dates ----------
today() { date -u +%Y-%m-%d; }

# A compatibility date a couple of weeks old is always supported by the installed workerd.
compat_date() {
  local d
  d="$(date -u -d '14 days ago' +%Y-%m-%d 2>/dev/null || date -u -v-14d +%Y-%m-%d 2>/dev/null || today)"
  printf '%s' "$d"
}

# ---------- package.json inspection (needs node, which this stack always has) ----------
need_node() {
  command -v node >/dev/null 2>&1 || die "node is required (the whole stack runs on it)."
}

# pkg_script <package.json> <name>  -> exit 0 if scripts.<name> exists
pkg_script() {
  node -e '
    const p = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.exit(p.scripts && p.scripts[process.argv[2]] ? 0 : 1);
  ' "$1" "$2"
}

# pkg_dep <package.json> <name> -> exit 0 if it is a (dev)dependency
pkg_dep() {
  node -e '
    const p = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const all = Object.assign({}, p.dependencies, p.devDependencies);
    process.exit(Object.prototype.hasOwnProperty.call(all, process.argv[2]) ? 0 : 1);
  ' "$1" "$2"
}

# pkg_field <package.json> <field> -> prints the string value, or nothing
pkg_field() {
  node -e '
    const p = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const v = p[process.argv[2]];
    if (typeof v === "string") process.stdout.write(v);
  ' "$1" "$2"
}

# ---------- naming ----------
# lowercase, [a-z0-9-] only, no npm scope
slugify() {
  printf '%s' "$1" | sed -e 's#^@[^/]*/##' | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

# github_owner_of <git-dir> -> owner from the origin remote (github.com/OWNER/repo), or nothing
github_owner_of() {
  local url
  url="$(git -C "$1" remote get-url origin 2>/dev/null || true)"
  printf '%s' "$url" | sed -n -e 's#.*github\.com[:/]\([^/]*\)/.*#\1#p'
}

# ---------- templating ----------
# The values file holds KEY=VALUE lines. render applies them to __KEY__ and {{KEY}} placeholders.
sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

# render <template> <values-file>  -> rendered text on stdout
render() {
  local tpl="$1" values="$2" tmp key val
  tmp="$(mktemp "${TMPDIR:-/tmp}/engpol-render.XXXXXX")"
  cat "$tpl" >"$tmp"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%=*}"
    val="${line#*=}"
    val="$(sed_escape "$val")"
    sed -e "s|__${key}__|${val}|g" -e "s|{{${key}}}|${val}|g" "$tmp" >"$tmp.next"
    mv "$tmp.next" "$tmp"
  done <"$values"
  cat "$tmp"
  rm -f "$tmp"
}
