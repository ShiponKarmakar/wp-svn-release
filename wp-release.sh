#!/usr/bin/env bash
#
# wp-release — universal, interactive WordPress.org plugin release tool.
#
# Drop into PATH (or use the alias from wp-release-setup.sh), cd into any
# plugin source folder, and run:  wprel <version>
#
# Usage:
#   wprel 1.2.3
#   wprel --help
#   wprel --reconfigure 1.2.3   # re-run the wizard before releasing
#   wprel --dry-run 1.2.3       # show what would change, don't touch SVN
#
# Required env vars (set once via wp-release-setup.sh):
#   WP_SVN_USER   your WordPress.org username
#   WP_SVN_BASE   base folder for SVN checkouts (default: ~/wp-svn)
#
# Per-plugin config (auto-saved by the wizard at the plugin source root):
#   .svnrelease   key=value file holding slug, main_file, svn_dir
#                 (also reads legacy .wprelease for backward compatibility)
#
# ─────────────────────────────────────────────────────────────────────
#   Author: Shipon Karmakar
#   Tested on macOS and Linux (bash 3.2+, POSIX tools)
# ─────────────────────────────────────────────────────────────────────
#
set -euo pipefail

# =============================== constants ===============================

SVNRELEASE_FILE=".svnrelease"
LEGACY_FILE=".wprelease"

# =============================== helpers =================================

die()  { printf "❌  %s\n" "$*" >&2; exit 1; }
info() { printf "ℹ️  %s\n" "$*"; }
ok()   { printf "✅  %s\n" "$*"; }
hr()   { printf -- "---------------------------------------------------------\n"; }

# ask <prompt> [default]  → echoes the answer (default if user hits Enter)
ask() {
  local prompt="$1" default="${2:-}" answer
  if [[ -n "$default" ]]; then
    printf "%s [%s]: " "$prompt" "$default" >&2
  else
    printf "%s: " "$prompt" >&2
  fi
  read -r answer
  if [[ -z "$answer" && -n "$default" ]]; then
    printf "%s" "$default"
  else
    printf "%s" "$answer"
  fi
}

# ask_yn <prompt> [Y|N=N]  → returns 0 for yes, 1 for no
ask_yn() {
  local prompt="$1" default="${2:-N}" hint answer
  case "$default" in
    Y|y) hint="[Y/n]"; default="Y" ;;
    *)   hint="[y/N]"; default="N" ;;
  esac
  printf "%s %s " "$prompt" "$hint" >&2
  read -r answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

show_help() {
  cat <<'EOF'
wp-release — universal WordPress.org plugin release tool

USAGE
  wprel <version>                 release a new version (e.g. wprel 1.2.3)
  wprel --reconfigure <version>   re-run the wizard before releasing
  wprel --dry-run <version>       show what would change, don't touch SVN
  wprel --help                    this message

REQUIRED ENV (set once with wp-release-setup.sh)
  WP_SVN_USER   your WordPress.org username
  WP_SVN_BASE   base folder for SVN checkouts (default: ~/wp-svn)

PER-PLUGIN CONFIG (auto-saved by the wizard)
  .wprelease    in the plugin source root, holds:
                  slug=my-plugin
                  main_file=my-plugin.php
                  svn_dir=/abs/path/to/svn-checkout

WHAT IT DOES
  1. Resolves config (env vars + .wprelease + auto-detection from CWD).
  2. Triple-validates the version arg against the main file's
     "Version:" header AND readme.txt's "Stable tag:".
  3. Refuses to overwrite an existing tag (WP.org tags are immutable).
  4. Scrubs .DS_Store / ._* from source.
  5. rsyncs source → trunk/ (honors .distignore if present).
  6. Reconciles svn add / svn rm.
  7. svn cp trunk → tags/<version>.
  8. Shows a preview, asks confirmation, then commits.
EOF
}

# =============================== arg parsing ============================

VERSION=""
RECONFIGURE=0
DRY_RUN=0

while (( $# > 0 )); do
  case "$1" in
    -h|--help)        show_help; exit 0 ;;
    --reconfigure)    RECONFIGURE=1 ;;
    --dry-run)        DRY_RUN=1 ;;
    -*)               die "Unknown flag: $1  (try --help)" ;;
    *)                if [[ -z "$VERSION" ]]; then VERSION="$1"; else die "Unexpected arg: $1"; fi ;;
  esac
  shift
done

[[ -n "$VERSION" ]] || die "Missing version. Try: wprel 1.2.3   (--help for more)"

# basic version sanity (X.Y or X.Y.Z, optional -beta etc.)
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}([.-][A-Za-z0-9]+)?$ ]] \
  || die "Version '$VERSION' doesn't look right. Expected e.g. 1.2.3"

# =============================== env =====================================

SVN_USER="${WP_SVN_USER:-}"
SVN_BASE="${WP_SVN_BASE:-$HOME/wp-svn}"

[[ -n "$SVN_USER" ]] || die "WP_SVN_USER is not set.
   Run wp-release-setup.sh once, or add to your shell profile:
        export WP_SVN_USER=\"your-wordpress-org-username\""

SRC_DIR="$(pwd)"

# =============================== detection ===============================

detect_main_file() {
  # echoes filename only (no path), or empty string if not found
  local match
  match="$(grep -lE '^[[:space:]]*\*[[:space:]]*Plugin Name:' "$SRC_DIR"/*.php 2>/dev/null | head -1 || true)"
  [[ -n "$match" ]] && basename "$match"
}

# =============================== .wprelease parser =======================

CFG_SLUG=""
CFG_MAIN_FILE=""
CFG_SVN_DIR=""

parse_wprelease() {
  local file="$1" line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"
    value="${value%\"}"; value="${value#\"}"
    value="${value%\'}"; value="${value#\'}"
    case "$key" in
      slug)      CFG_SLUG="$value" ;;
      main_file) CFG_MAIN_FILE="$value" ;;
      svn_dir)   CFG_SVN_DIR="$value" ;;
    esac
  done < "$file"
}

write_wprelease() {
  local file="$SRC_DIR/$SVNRELEASE_FILE"
  cat > "$file" <<EOF
# wp-release per-plugin config (auto-generated). Edit freely; safe to commit.
slug=$CFG_SLUG
main_file=$CFG_MAIN_FILE
svn_dir=$CFG_SVN_DIR
EOF
  ok "Saved config to $file"
}

# =============================== wizard ==================================

run_wizard() {
  echo
  hr
  echo "  Plugin release wizard — confirm or change each value:"
  hr

  local detected_slug detected_main
  detected_slug="$(basename "$SRC_DIR")"
  detected_main="$(detect_main_file || true)"

  CFG_SLUG="$(ask "Plugin slug (WP.org repo name)" "${CFG_SLUG:-$detected_slug}")"
  CFG_MAIN_FILE="$(ask "Main plugin PHP file" "${CFG_MAIN_FILE:-${detected_main:-$CFG_SLUG.php}}")"
  CFG_SVN_DIR="$(ask "SVN checkout folder" "${CFG_SVN_DIR:-$SVN_BASE/$CFG_SLUG}")"

  echo
  if ask_yn "Save these answers to $SVNRELEASE_FILE so we don't ask again?" Y; then
    write_wprelease
  else
    info "Not saving. You'll be asked again next release."
  fi
}

# =============================== resolve config ==========================

# Look for the new .svnrelease first, then fall back to legacy .wprelease.
ACTIVE_CONFIG_FILE=""
if [[ -f "$SRC_DIR/$SVNRELEASE_FILE" ]]; then
  ACTIVE_CONFIG_FILE="$SRC_DIR/$SVNRELEASE_FILE"
elif [[ -f "$SRC_DIR/$LEGACY_FILE" ]]; then
  ACTIVE_CONFIG_FILE="$SRC_DIR/$LEGACY_FILE"
fi

if [[ -n "$ACTIVE_CONFIG_FILE" && $RECONFIGURE -eq 0 ]]; then
  parse_wprelease "$ACTIVE_CONFIG_FILE"
fi

[[ -z "$CFG_SLUG" ]]      && CFG_SLUG="$(basename "$SRC_DIR")"
[[ -z "$CFG_MAIN_FILE" ]] && CFG_MAIN_FILE="$(detect_main_file || true)"
[[ -z "$CFG_SVN_DIR" ]]   && CFG_SVN_DIR="$SVN_BASE/$CFG_SLUG"

if [[ -z "$ACTIVE_CONFIG_FILE" || $RECONFIGURE -eq 1 ]]; then
  run_wizard
else
  echo
  hr
  printf "  Plugin slug:   %s\n" "$CFG_SLUG"
  printf "  Source:        %s\n" "$SRC_DIR"
  printf "  Main file:     %s\n" "$CFG_MAIN_FILE"
  printf "  SVN checkout:  %s\n" "$CFG_SVN_DIR"
  printf "  Releasing as:  v%s\n" "$VERSION"
  printf "  Username:      %s\n" "$SVN_USER"
  hr
  echo
  printf "Use this config? [Y/n/edit]: " >&2
  read -r ans
  case "$ans" in
    ""|Y|y|Yes|yes)  : ;;
    e|E|edit)        run_wizard ;;
    *)               die "Aborted by user." ;;
  esac
fi

# =============================== validate ================================

[[ -n "$CFG_MAIN_FILE" ]] \
  || die "No main plugin file detected. Add a *.php file with a 'Plugin Name:' header,
        or run with --reconfigure to set it manually."

[[ -f "$SRC_DIR/$CFG_MAIN_FILE" ]] \
  || die "main_file '$CFG_MAIN_FILE' not found in $SRC_DIR.
        Run with --reconfigure to fix."

SRC_VERSION="$(grep -E '^[[:space:]]*\*[[:space:]]*Version:' "$SRC_DIR/$CFG_MAIN_FILE" \
                 | awk '{print $NF}' | head -1)"
[[ "$SRC_VERSION" == "$VERSION" ]] \
  || die "Version mismatch in $CFG_MAIN_FILE
        File says:  '$SRC_VERSION'
        You asked:  '$VERSION'
        Bump the Version: header before releasing."

if [[ -f "$SRC_DIR/readme.txt" ]]; then
  README_TAG="$(awk '/^Stable tag:/{print $NF; exit}' "$SRC_DIR/readme.txt")"
  [[ "$README_TAG" == "$VERSION" ]] \
    || die "Version mismatch in readme.txt
        Stable tag:  '$README_TAG'
        You asked:   '$VERSION'
        Bump the Stable tag before releasing."
else
  info "No readme.txt found — skipping Stable tag check."
fi

if [[ ! -d "$CFG_SVN_DIR/.svn" ]]; then
  echo
  info "No SVN checkout at: $CFG_SVN_DIR"
  if ask_yn "Run 'svn checkout' for slug '$CFG_SLUG' now?" N; then
    mkdir -p "$(dirname "$CFG_SVN_DIR")"
    svn checkout "https://plugins.svn.wordpress.org/$CFG_SLUG" "$CFG_SVN_DIR"
  else
    die "Cannot continue without an SVN checkout. To do it manually:
          mkdir -p \"$(dirname "$CFG_SVN_DIR")\"
          svn checkout https://plugins.svn.wordpress.org/$CFG_SLUG \"$CFG_SVN_DIR\""
  fi
fi

# =============================== final summary ===========================

echo
hr
printf "  Plugin slug:   %s\n" "$CFG_SLUG"
printf "  Source:        %s\n" "$SRC_DIR"
printf "  Main file:     %s\n" "$CFG_MAIN_FILE"
printf "  SVN checkout:  %s\n" "$CFG_SVN_DIR"
printf "  Releasing as:  v%s\n" "$VERSION"
printf "  Username:      %s\n" "$SVN_USER"
(( DRY_RUN )) && printf "  Mode:          DRY RUN (no SVN writes)\n"
hr
echo

# =============================== sync ====================================

info "Updating SVN checkout…"
( cd "$CFG_SVN_DIR" && svn update --quiet )

if ( cd "$CFG_SVN_DIR" && svn info "tags/$VERSION" >/dev/null 2>&1 ); then
  die "tags/$VERSION already exists in SVN. Tags are immutable; pick a new version."
fi

info "Scrubbing macOS junk from source…"
find "$SRC_DIR" \( -name ".DS_Store" -o -name "._*" \) -delete 2>/dev/null || true

RSYNC_FLAGS=( -a --delete )
(( DRY_RUN )) && RSYNC_FLAGS+=( -n -v )

# Critical safety excludes — applied ALWAYS, even when .distignore is present.
# These should NEVER be shipped to WP.org SVN under any circumstances.
RSYNC_FLAGS+=(
  --exclude=.git --exclude=.gitignore --exclude=.gitattributes --exclude=.github
  --exclude=.DS_Store --exclude='._*' --exclude=Thumbs.db
  --exclude=.svnrelease --exclude=.wprelease --exclude=.distignore
)

# Project-specific excludes — additive on top of the safety excludes above.
if [[ -f "$SRC_DIR/.distignore" ]]; then
  info "Using .distignore for additional rsync excludes."
  RSYNC_FLAGS+=( --exclude-from="$SRC_DIR/.distignore" )
else
  RSYNC_FLAGS+=(
    --exclude=.idea --exclude=.vscode
    --exclude=node_modules
    --exclude='.phpcs.xml*' --exclude='phpcs.xml*'
    --exclude='phpunit.xml*' --exclude='composer.*'
    --exclude='package*.json' --exclude=yarn.lock
    --exclude=tests
  )
fi

info "Syncing source → trunk/…"
rsync "${RSYNC_FLAGS[@]}" "$SRC_DIR/" "$CFG_SVN_DIR/trunk/" | tail -20

if (( DRY_RUN )); then
  echo
  ok "Dry run complete. No SVN changes made."
  exit 0
fi

# =============================== reconcile svn ===========================

info "Reconciling SVN with the synced files…"
cd "$CFG_SVN_DIR"
svn add --force --quiet trunk/* 2>/dev/null || true
# portable replacement for `xargs -r` (BSD xargs lacks -r)
svn status trunk | awk '/^!/ {print $2}' | while IFS= read -r missing; do
  [[ -n "$missing" ]] && svn rm --force "$missing" >/dev/null 2>&1 || true
done

info "Creating tags/$VERSION (snapshot of trunk)…"
svn cp trunk "tags/$VERSION"

# =============================== preview & commit ========================

echo
echo "==================== About to commit ===================="
svn status | head -40
TOTAL_CHANGES=$(svn status | wc -l | tr -d ' ')
printf "  …  (%s total changes)\n" "$TOTAL_CHANGES"
echo "========================================================="
echo

if ask_yn "Commit as v$VERSION?" N; then
  info "Committing…"
  svn ci -m "Release v$VERSION" --username "$SVN_USER"
  echo
  ok "v$VERSION pushed to https://plugins.svn.wordpress.org/$CFG_SLUG"
  ok "Public page updates within ~15 min: https://wordpress.org/plugins/$CFG_SLUG/"
else
  die "Aborted. To undo local changes:  cd \"$CFG_SVN_DIR\" && svn revert -R ."
fi
