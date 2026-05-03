#!/usr/bin/env bash
#
# wp-release-setup — universal setup wizard for the wp-release tool.
#
# A friendly two-phase wizard that gets any developer ready to publish
# WordPress.org plugin releases via SVN with a single command.
#
#   Phase 1  Machine setup  (asked ONCE per developer)
#            - WP.org username
#            - default SVN checkouts base folder
#            - alias name
#            - which shell profile to update
#            → appends export+alias lines to your shell profile
#
#   Phase 2  Plugin setup   (asked ONCE per plugin)
#            - plugin source folder (where you develop)
#            - plugin slug, main PHP file (auto-detected)
#            - SVN checkout folder (where trunk/tags/assets live)
#            - marketing assets source folder (optional)
#            - per-plugin shortcut alias (optional)
#            → writes .svnrelease in the plugin source folder
#
# After this wizard, every release is just:    wprel <version>
#
# Usage:   ./wp-release-setup.sh
# Re-run anytime — for a new plugin, or to reconfigure an existing one.
#
# ─────────────────────────────────────────────────────────────────────
#   Author: Shipon Karmakar
#   Tested on macOS and Linux (bash 3.2+, POSIX tools)
# ─────────────────────────────────────────────────────────────────────
#
set -euo pipefail

# ============================== constants ==============================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RELEASE_SCRIPT="$SCRIPT_DIR/wp-release.sh"
SVNRELEASE_FILE=".svnrelease"          # current per-plugin config name
LEGACY_FILE=".svnrelease"               # backward-compat: read this if .svnrelease isn't present

# ANSI colors — auto-disabled when not on a TTY or NO_COLOR is set
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""
fi

# ============================== helpers ================================

die()  { printf "${C_RED}❌  %s${C_RESET}\n" "$*" >&2; exit 1; }
info() { printf "${C_CYAN}ℹ️  %s${C_RESET}\n" "$*"; }
ok()   { printf "${C_GREEN}✅  %s${C_RESET}\n" "$*"; }
warn() { printf "${C_YELLOW}⚠️  %s${C_RESET}\n" "$*"; }
hr()   { printf -- "${C_DIM}═════════════════════════════════════════════════════════════${C_RESET}\n"; }
sub()  { printf -- "${C_DIM}─────────────────────────────────────────────────────────────${C_RESET}\n"; }

section() {
  echo
  hr
  printf "  ${C_BOLD}%s${C_RESET}\n" "$*"
  hr
}

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

# Print a multi-line prompt block with helper text + default + a typed-input line.
# Used by ask_path / ask_slug / ask_filename below.
prompt_block() {
  local title="$1" hint="$2" example="$3" default="$4" input_label="$5"
  echo >&2
  printf "  ${C_BOLD}%s${C_RESET}\n" "$title" >&2
  [[ -n "$hint" ]]    && printf "    ${C_DIM}%s${C_RESET}\n" "$hint" >&2
  [[ -n "$example" ]] && printf "    ${C_DIM}Example: %s${C_RESET}\n" "$example" >&2
  if [[ -n "$default" ]]; then
    printf "    ↳ detected: ${C_CYAN}%s${C_RESET}\n" "$default" >&2
    printf "    ↳ Press ${C_BOLD}Enter${C_RESET} to accept, or type a different %s: " "$input_label" >&2
  else
    printf "    ↳ %s: " "$input_label" >&2
  fi
}

# Reject URLs and other obviously-not-a-local-path input.
looks_like_url() {
  [[ "$1" =~ ^https?:// ]] || [[ "$1" =~ ^svn:// ]]
}

# ask_path <title> <hint> <example> [default] [must_exist=no|yes]
# For LOCAL folder paths. Loops on bad/empty input. Refuses URLs.
ask_path() {
  local title="$1" hint="$2" example="$3" default="${4:-}" must_exist="${5:-no}" answer
  while true; do
    prompt_block "$title" "$hint" "$example" "$default" "path"
    read -r answer
    answer="${answer:-$default}"
    if [[ -z "$answer" ]]; then
      warn "Path can't be empty."
      ask_yn "  Try again?" Y || die "Aborted by user."
      continue
    fi
    if looks_like_url "$answer"; then
      warn "That looks like a URL ($answer)."
      warn "This field wants a LOCAL folder on your disk, not a URL."
      ask_yn "  Try again?" Y || die "Aborted by user."
      continue
    fi
    # expand leading ~ to $HOME
    case "$answer" in
      "~"|"~/"*) answer="$HOME${answer#~}" ;;
    esac
    if [[ "$must_exist" == "yes" && ! -d "$answer" ]]; then
      warn "Folder doesn't exist: $answer"
      ask_yn "  Try again?" Y || die "Aborted by user."
      continue
    fi
    printf "%s" "$answer"
    return 0
  done
}

# ask_slug <title> <hint> <example> [default]
# WP.org slugs are short — lowercase, alphanumerics, hyphens only.
# If user pastes a URL, extract the slug from it automatically.
ask_slug() {
  local title="$1" hint="$2" example="$3" default="${4:-}" answer extracted
  while true; do
    prompt_block "$title" "$hint" "$example" "$default" "slug"
    read -r answer
    answer="${answer:-$default}"
    # auto-extract slug if user pasted a URL
    if looks_like_url "$answer"; then
      extracted="$(printf "%s" "$answer" | sed -E 's|^https?://[^/]+/||; s|/.*$||; s|/$||')"
      if [[ -n "$extracted" ]]; then
        info "Extracted slug from URL: $extracted"
        answer="$extracted"
      fi
    fi
    if [[ "$answer" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      printf "%s" "$answer"
      return 0
    fi
    warn "Invalid slug: '$answer'"
    warn "Slugs must be lowercase letters, digits, and hyphens only (e.g. my-cool-plugin)."
    ask_yn "  Try again?" Y || die "Aborted by user."
  done
}

# ask_filename <title> <hint> <example> [default] [must_exist_in_dir]
# For a single filename (no slashes). Optionally verifies it exists in a given dir.
ask_filename() {
  local title="$1" hint="$2" example="$3" default="${4:-}" must_exist_in="${5:-}" answer
  while true; do
    prompt_block "$title" "$hint" "$example" "$default" "filename"
    read -r answer
    answer="${answer:-$default}"
    if [[ -z "$answer" ]]; then
      warn "Filename can't be empty."
      ask_yn "  Try again?" Y || die "Aborted by user."
      continue
    fi
    if [[ "$answer" == */* ]]; then
      warn "That has a slash — this field wants a FILENAME ONLY, not a path."
      warn "(Got: $answer)"
      ask_yn "  Try again?" Y || die "Aborted by user."
      continue
    fi
    if [[ -n "$must_exist_in" && ! -f "$must_exist_in/$answer" ]]; then
      warn "File not found: $must_exist_in/$answer"
      ask_yn "  Try again?" Y || die "Aborted by user."
      continue
    fi
    printf "%s" "$answer"
    return 0
  done
}

ask_yn() {
  local prompt="$1" default="${2:-N}" hint answer
  case "$default" in
    Y|y) hint="${C_BOLD}[Y/n]${C_RESET}"; default="Y" ;;
    *)   hint="${C_BOLD}[y/N]${C_RESET}"; default="N" ;;
  esac
  while true; do
    printf "%s %s " "$prompt" "$hint" >&2
    read -r answer
    answer="${answer:-$default}"
    case "$answer" in
      Y|y|Yes|yes|YES)  return 0 ;;
      N|n|No|no|NO)     return 1 ;;
      *) printf "${C_YELLOW}  Please answer Y or N (or press Enter for the default).${C_RESET}\n" >&2 ;;
    esac
  done
}

# ============================ verify install ===========================

[[ -f "$RELEASE_SCRIPT" ]] \
  || die "Can't find wp-release.sh next to this setup script.
        Expected at: $RELEASE_SCRIPT
        Both files must live in the same folder."

chmod +x "$RELEASE_SCRIPT" 2>/dev/null || true

# ============================ profile detection ========================

detect_profile() {
  case "$(basename "${SHELL:-}")" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) if [[ -f "$HOME/.bashrc" ]]; then echo "$HOME/.bashrc"
          else echo "$HOME/.bash_profile"; fi ;;
    *)    echo "$HOME/.profile" ;;
  esac
}

DEFAULT_PROFILE="$(detect_profile)"

is_machine_configured() {
  local profile="$1"
  [[ -f "$profile" ]] || return 1
  grep -qE '^[[:space:]]*export[[:space:]]+WP_SVN_USER=' "$profile" 2>/dev/null
}

read_alias_from_profile() {
  local profile="$1"
  [[ -f "$profile" ]] || return 1
  grep -E "^[[:space:]]*alias[[:space:]]+[A-Za-z_][A-Za-z0-9_-]*=['\"]?.*wp-release\.sh" "$profile" 2>/dev/null \
    | head -1 \
    | sed -E "s/^[[:space:]]*alias[[:space:]]+([A-Za-z_][A-Za-z0-9_-]*)=.*/\1/"
}

# ============================ phase 1: machine =========================

WP_USER=""
WP_BASE=""
ALIAS_NAME=""
PROFILE=""

phase1_machine_setup() {
  section "Phase 1 — Machine setup (one time per developer)"
  echo
  echo "  These are MACHINE-WIDE settings that apply to every plugin you"
  echo "  ever release. The wizard only asks for your username — the rest"
  echo "  uses safe defaults you can edit by hand later if needed."
  echo

  # Username is the ONLY thing the wizard collects in Phase 1. Everything
  # else is locked to safe defaults to prevent accidental misconfiguration.
  while true; do
    WP_USER="$(ask "Your WordPress.org username")"
    if [[ -z "$WP_USER" ]]; then
      warn "Username can't be empty."; continue
    fi
    if ! [[ "$WP_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
      warn "Invalid username: '$WP_USER' (letters, digits, dot, underscore, hyphen only)"; continue
    fi
    break
  done

  # Hardcoded sensible defaults — no customization in the wizard.
  WP_BASE="$HOME/wp-svn"
  ALIAS_NAME="wprel"
  PROFILE="$DEFAULT_PROFILE"

  # Show what's about to happen.
  echo
  sub
  printf "  About to install on this machine:\n"
  printf "    WP.org username:    %s\n" "$WP_USER"
  printf "    SVN checkouts base: %s\n" "$WP_BASE"
  printf "    Shell alias:        %s\n" "$ALIAS_NAME"
  printf "    Shell profile:      %s\n" "$PROFILE"
  sub
  echo
  echo "  Need different values? Edit $PROFILE by hand after the wizard finishes."
  echo

  if ! ask_yn "Continue with these settings?" Y; then
    die "Aborted by user."
  fi

  local timestamp snippet
  timestamp="$(date +%Y-%m-%d)"
  snippet=$(cat <<EOF

# --- wp-release (added by wp-release-setup.sh on $timestamp) ---
export WP_SVN_USER="$WP_USER"
export WP_SVN_BASE="$WP_BASE"
alias $ALIAS_NAME='$RELEASE_SCRIPT'
# --- end wp-release ---
EOF
)

  echo
  sub
  printf "  About to append the following to: %s\n" "$PROFILE"
  sub
  printf "%s\n" "$snippet"
  sub
  echo

  if [[ ! -d "$WP_BASE" ]]; then
    if ask_yn "Base folder $WP_BASE doesn't exist. Create it?" Y; then
      mkdir -p "$WP_BASE"
      ok "Created $WP_BASE"
    fi
  fi

  if [[ -f "$PROFILE" ]] && grep -q "wp-release-setup.sh" "$PROFILE" 2>/dev/null; then
    warn "$PROFILE already has a wp-release block."
    warn "Appending again will leave both — you may want to delete the old block manually."
  fi

  if ask_yn "Append the snippet above to $PROFILE now?" Y; then
    printf "%s\n" "$snippet" >> "$PROFILE"
    ok "Appended to $PROFILE"
    info "Reload your shell so it takes effect:    source \"$PROFILE\""
  else
    info "Skipped writing to $PROFILE. To install manually, paste the snippet above."
  fi

  # Make available to phase 2 in this same process
  export WP_SVN_USER="$WP_USER"
  export WP_SVN_BASE="$WP_BASE"
}

# ============================ plugin detection =========================

detect_main_file_in() {
  local dir="$1" match
  match="$(grep -lE '^[[:space:]]*\*[[:space:]]*Plugin Name:' "$dir"/*.php 2>/dev/null | head -1 || true)"
  [[ -n "$match" ]] && basename "$match"
}

is_plugin_folder() {
  local dir="$1"
  [[ -n "$(detect_main_file_in "$dir")" ]]
}

# ============================ .svnrelease parsing =======================

EXISTING_SLUG=""
EXISTING_MAIN=""
EXISTING_SVN=""
EXISTING_ASSETS=""

parse_existing_wprelease() {
  local file="$1" line key value
  EXISTING_SLUG=""; EXISTING_MAIN=""; EXISTING_SVN=""; EXISTING_ASSETS=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue
    key="${line%%=*}"; value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}";   key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"
    value="${value%\"}"; value="${value#\"}"; value="${value%\'}"; value="${value#\'}"
    case "$key" in
      slug)       EXISTING_SLUG="$value" ;;
      main_file)  EXISTING_MAIN="$value" ;;
      svn_dir)    EXISTING_SVN="$value" ;;
      assets_src) EXISTING_ASSETS="$value" ;;
    esac
  done < "$file"

  # Sanitize: drop any value that's obviously corrupt so it's not used as a default.
  if [[ -n "$EXISTING_SLUG" ]] && ! [[ "$EXISTING_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    warn "Ignoring invalid slug from .svnrelease: $EXISTING_SLUG"
    EXISTING_SLUG=""
  fi
  if [[ -n "$EXISTING_MAIN" && "$EXISTING_MAIN" == */* ]]; then
    warn "Ignoring invalid main_file from .svnrelease (had a slash): $EXISTING_MAIN"
    EXISTING_MAIN=""
  fi
  if [[ -n "$EXISTING_SVN" ]] && looks_like_url "$EXISTING_SVN"; then
    warn "Ignoring invalid svn_dir from .svnrelease (was a URL): $EXISTING_SVN"
    EXISTING_SVN=""
  fi
  if [[ -n "$EXISTING_ASSETS" ]] && looks_like_url "$EXISTING_ASSETS"; then
    warn "Ignoring invalid assets_src from .svnrelease (was a URL): $EXISTING_ASSETS"
    EXISTING_ASSETS=""
  fi
}

# ============================ phase 2: plugin ==========================

phase2_plugin_setup() {
  section "Phase 2 — Plugin setup (one time per plugin)"
  echo
  echo "  Linking your plugin SOURCE folder to its SVN folder."
  echo

  local source_dir slug main_file svn_dir assets_src
  local cur_ver cur_stable
  local has_svn has_trunk has_tags has_assets tag_count

  # --- defaults from existing .svnrelease, if any ---
  if [[ -f "$PWD/$SVNRELEASE_FILE" ]]; then
    info "Found existing $SVNRELEASE_FILE — pre-filling answers."
    parse_existing_wprelease "$PWD/$SVNRELEASE_FILE"
  elif [[ -f "$PWD/$LEGACY_FILE" ]]; then
    info "Found legacy $LEGACY_FILE — migrating answers to $SVNRELEASE_FILE."
    parse_existing_wprelease "$PWD/$LEGACY_FILE"
  fi

  # 2.1 source folder
  source_dir="$(ask_path \
    "Plugin source folder (where you develop)" \
    "Local folder containing *.php and readme.txt." \
    "/Users/you/Herd/.../wp-content/plugins/my-plugin" \
    "$PWD" yes)"
  source_dir="$( cd "$source_dir" && pwd )"   # absolute

  is_plugin_folder "$source_dir" \
    || warn "No *.php with 'Plugin Name:' header found in $source_dir.
       You can continue, but the version validation may fail later."

  # 2.2 slug + main file (auto-detect, then confirm)
  local detected_slug detected_main
  detected_slug="${EXISTING_SLUG:-$(basename "$source_dir")}"
  detected_main="${EXISTING_MAIN:-$(detect_main_file_in "$source_dir" || true)}"

  slug="$(ask_slug \
    "Plugin slug (the WP.org repo name)" \
    "Short, lowercase, hyphens only — NOT a URL." \
    "my-plugin-slug" \
    "$detected_slug")"

  main_file="$(ask_filename \
    "Main plugin PHP file" \
    "Filename only (no path) — the .php file with the 'Plugin Name:' header." \
    "${slug}.php" \
    "${detected_main:-$slug.php}" \
    "$source_dir")"

  # parse current version + stable tag for display only
  cur_ver=""
  if [[ -f "$source_dir/$main_file" ]]; then
    cur_ver="$(grep -E '^[[:space:]]*\*[[:space:]]*Version:' "$source_dir/$main_file" 2>/dev/null \
                 | awk '{print $NF}' | head -1 || true)"
  fi
  [[ -z "$cur_ver" ]] && cur_ver="(not found)"

  if [[ -f "$source_dir/readme.txt" ]]; then
    cur_stable="$(awk '/^Stable tag:/{print $NF; exit}' "$source_dir/readme.txt" 2>/dev/null || true)"
    [[ -z "$cur_stable" ]] && cur_stable="(not found)"
  else
    cur_stable="(no readme.txt)"
  fi

  # 2.3 SVN folder
  local default_svn
  default_svn="${EXISTING_SVN:-${WP_SVN_BASE:-$HOME/wp-svn}/$slug}"
  svn_dir="$(ask_path \
    "SVN checkout folder" \
    "LOCAL folder on your disk where trunk/, tags/, assets/ live (NOT a URL)." \
    "/Users/you/wp-svn/${slug}" \
    "$default_svn" no)"

  if [[ ! -d "$svn_dir" ]]; then
    echo
    warn "SVN folder doesn't exist: $svn_dir"
    if ask_yn "Run 'svn checkout https://plugins.svn.wordpress.org/$slug' now?" N; then
      mkdir -p "$(dirname "$svn_dir")"
      svn checkout "https://plugins.svn.wordpress.org/$slug" "$svn_dir" \
        || warn "svn checkout failed. You can run it manually later."
    else
      warn "Skipped. wprel will fail until this folder is a valid SVN checkout."
    fi
  fi

  # validate inside the svn folder
  has_svn="✗"; has_trunk="✗"; has_tags="✗"; has_assets="✗"; tag_count=""
  [[ -d "$svn_dir/.svn" ]]   && has_svn="✓"
  [[ -d "$svn_dir/trunk" ]]  && has_trunk="✓"
  [[ -d "$svn_dir/tags" ]]   && has_tags="✓"
  [[ -d "$svn_dir/assets" ]] && has_assets="✓"
  if [[ -d "$svn_dir/tags" ]]; then
    tag_count="$(find "$svn_dir/tags" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    tag_count=" ($tag_count existing release tags)"
  fi

  # 2.4 marketing assets (optional)
  echo
  echo "  Marketing assets (OPTIONAL):"
  echo "    PNG files for your plugin's WP.org listing page —"
  echo "    banners, icons, screenshots. They live in <svn>/assets/."
  echo "    Filenames: banner-1544x500.png, icon-256x256.png, screenshot-1.png, …"
  echo
  echo "  Skip this if you manage assets manually or don't have any yet."
  echo

  local assets_default_yn="N"
  [[ -n "${EXISTING_ASSETS:-}" ]] && assets_default_yn="Y"
  assets_src=""
  if ask_yn "  Do you have a local folder with marketing PNGs to sync?" "$assets_default_yn"; then
    echo
    echo "  Marketing assets folder"
    echo "    Local folder containing banner-*.png, icon-*.png, screenshot-*.png."
    echo "    Example: /Users/you/marketing-assets/my-plugin"
    if [[ -n "${EXISTING_ASSETS:-}" ]]; then
      echo "    ↳ detected: ${EXISTING_ASSETS}"
    fi
    printf "    ↳ Type a path (or press Enter to skip): " >&2
    read -r assets_src
    assets_src="${assets_src:-${EXISTING_ASSETS:-}}"
    if [[ -z "$assets_src" ]]; then
      info "  Empty path — skipping marketing assets."
    elif looks_like_url "$assets_src"; then
      warn "  That looks like a URL. Skipping marketing assets."
      assets_src=""
    elif [[ ! -d "$assets_src" ]]; then
      warn "  Folder doesn't exist: $assets_src"
      if ! ask_yn "  Save it anyway?" N; then
        assets_src=""
        info "  Skipped marketing assets."
      fi
    fi
  else
    info "  Skipped — no marketing assets folder configured."
  fi

  # 2.5 summary
  echo
  hr
  printf "  Plugin:               %s\n" "$slug"
  printf "  WP.org page:          https://wordpress.org/plugins/%s/\n" "$slug"
  printf "  SVN repository:       https://plugins.svn.wordpress.org/%s/\n" "$slug"
  echo
  echo "  ─── Source side (development) ───"
  printf "  Source folder:        %s\n" "$source_dir"
  printf "  Main PHP file:        %s\n" "$main_file"
  printf "  Detected version:     %s   (Version: header)\n" "$cur_ver"
  printf "  Detected stable tag:  %s   (readme.txt)\n" "$cur_stable"
  echo
  echo "  ─── SVN side (releases) ───"
  printf "  SVN working copy:     %s\n" "$svn_dir"
  printf "    [%s] .svn/ working copy\n" "$has_svn"
  printf "    [%s] trunk/\n" "$has_trunk"
  printf "    [%s] tags/%s\n" "$has_tags" "$tag_count"
  printf "    [%s] assets/\n" "$has_assets"
  echo
  if [[ -n "$assets_src" ]]; then
    printf "  Marketing assets src: %s\n" "$assets_src"
  else
    printf "  Marketing assets src: (none — managed manually inside SVN assets/)\n"
  fi
  hr
  echo

  # 2.6 save .svnrelease
  echo "  Will write to: $source_dir/$SVNRELEASE_FILE"
  echo
  echo "  ┌──────────────────────────────────────────────────────────"
  echo "  │ # wp-release per-plugin config (managed by wp-release-setup.sh)"
  echo "  │ slug=$slug"
  echo "  │ main_file=$main_file"
  echo "  │ svn_dir=$svn_dir"
  echo "  │ assets_src=$assets_src"
  echo "  └──────────────────────────────────────────────────────────"
  echo

  if ask_yn "Save this config to $SVNRELEASE_FILE?" Y; then
    cat > "$source_dir/$SVNRELEASE_FILE" <<EOF
# wp-release per-plugin config (managed by wp-release-setup.sh)
# Safe to commit — contains no secrets.
slug=$slug
main_file=$main_file
svn_dir=$svn_dir
assets_src=$assets_src
EOF
    ok "Saved to $source_dir/$SVNRELEASE_FILE"
  else
    info "Not saved. wprel will run its own wizard the first time you release."
  fi

  # 2.7 per-plugin shortcut alias (optional)
  setup_per_plugin_alias "$slug" "$source_dir"

  # 2.8 closing
  local universal_alias="${ALIAS_NAME:-$(read_alias_from_profile "$DEFAULT_PROFILE" || echo wprel)}"
  [[ -n "$universal_alias" ]] || universal_alias="wprel"
  local profile_to_reload="${PROFILE:-$DEFAULT_PROFILE}"

  echo
  hr
  printf "  ${C_GREEN}${C_BOLD}✅  Setup complete for: %s${C_RESET}\n" "$slug"
  hr
  echo
  printf "  ${C_BOLD}▸ Step 1 — Reload your shell so new aliases take effect:${C_RESET}\n"
  printf "        ${C_CYAN}source %s${C_RESET}\n" "$profile_to_reload"
  echo
  printf "  ${C_BOLD}▸ Step 2 — Verify the aliases are loaded:${C_RESET}\n"
  printf "        ${C_CYAN}type %s${C_RESET}\n" "$universal_alias"
  if [[ -n "${PLUGIN_ALIAS_ADDED:-}" ]]; then
    printf "        ${C_CYAN}type %s${C_RESET}\n" "$PLUGIN_ALIAS_ADDED"
  fi
  echo
  printf "  ${C_BOLD}▸ Step 3 — Release a new version:${C_RESET}\n"
  printf "      ${C_DIM}# bump the Version: header in your main PHP file${C_RESET}\n"
  printf "      ${C_DIM}# bump 'Stable tag:' in readme.txt${C_RESET}\n"
  printf "      ${C_DIM}# then:${C_RESET}\n"
  printf "        ${C_CYAN}%s --dry-run <version>${C_RESET}    ${C_DIM}# preview, no changes${C_RESET}\n" "$universal_alias"
  printf "        ${C_CYAN}%s <version>${C_RESET}              ${C_DIM}# real release${C_RESET}\n" "$universal_alias"
  if [[ -n "${PLUGIN_ALIAS_ADDED:-}" ]]; then
    echo
    printf "      ${C_DIM}or use the per-plugin alias from ANY folder:${C_RESET}\n"
    printf "        ${C_CYAN}%s <version>${C_RESET}\n" "$PLUGIN_ALIAS_ADDED"
  fi
  echo
  printf "  ${C_BOLD}▸ To configure another plugin:${C_RESET}\n"
  printf "        ${C_CYAN}cd /path/to/another/plugin && %s${C_RESET}\n" "$0"
  hr
  echo
}

# ====================== per-plugin alias helpers =======================

# Suggest an alias from the slug — first letter of each hyphenated word + "rel".
suggest_plugin_alias() {
  # Recommend an alias name that's clearly related to the plugin slug.
  # Uses the first meaningful word of the slug + "rel" — easy to remember
  # and obviously connected to the plugin (vs cryptic initials).
  #
  # Examples:
  #   domain-search-for-whmcs  →  domainrel
  #   extra-fields-for-acf     →  extrarel
  #   sendforce-mail-relay     →  sendforcerel
  #   bb-press                 →  bbpressrel  (first word too short → join 2 words)
  local slug="$1" base
  base="${slug%%-*}"
  if [[ ${#base} -lt 4 && "$slug" == *-* ]]; then
    local rest="${slug#*-}"
    base="${base}${rest%%-*}"
  fi
  printf "%srel" "$base"
}

alias_exists_in_profile() {
  local name="$1" profile="$2"
  [[ -f "$profile" ]] || return 1
  grep -qE "^[[:space:]]*alias[[:space:]]+${name}=" "$profile"
}

# alias_points_to_dir <name> <profile> <source_dir>
# Returns 0 if the alias already exists AND its target line references the
# given source_dir (i.e. it's the same plugin's alias). Used so a re-run
# doesn't treat an existing-correct alias as a conflict.
alias_points_to_dir() {
  local name="$1" profile="$2" source_dir="$3" line
  [[ -f "$profile" ]] || return 1
  line="$(grep -E "^[[:space:]]*alias[[:space:]]+${name}=" "$profile" | head -1)"
  [[ -n "$line" ]] || return 1
  # Compare by substring — paths can vary in quoting style
  case "$line" in
    *"\"$source_dir\""*) return 0 ;;
    *"'$source_dir'"*)   return 0 ;;
    *"$source_dir "*)    return 0 ;;
    *"$source_dir\""*)   return 0 ;;
  esac
  return 1
}

update_aliases_md() {
  local alias_name="$1" slug="$2" source_dir="$3"
  local md="$SCRIPT_DIR/ALIASES.md" today
  today="$(date +%Y-%m-%d)"
  if [[ ! -f "$md" ]]; then
    cat > "$md" <<'EOF'
# Plugin release aliases

Auto-maintained by `wp-release-setup.sh`. One row per per-plugin alias on this machine.
Run the wizard from a plugin source folder to add a new row.

| Alias | Plugin slug | Source folder | Added |
|---|---|---|---|
EOF
  fi
  printf "| \`%s\` | %s | \`%s\` | %s |\n" "$alias_name" "$slug" "$source_dir" "$today" >> "$md"
  ok "Logged alias to $md"
}

PLUGIN_ALIAS_ADDED=""

setup_per_plugin_alias() {
  local slug="$1" source_dir="$2"
  echo
  sub
  echo "  Optional: per-plugin shortcut alias"
  sub
  echo
  echo "  An alias lets you release this plugin from ANY folder, no cd needed:"
  echo "      \$ <alias> 1.2.3      # = cd into source folder, run wprel 1.2.3"
  echo
  echo "  Skip this if you prefer to always cd into the plugin folder first."
  echo

  if ! ask_yn "  Add a shortcut alias for this plugin?" N; then
    info "  Skipped. (You can re-run the wizard later to add one.)"
    return 0
  fi

  local profile="${PROFILE:-$DEFAULT_PROFILE}" suggested alias_name snippet
  suggested="$(suggest_plugin_alias "$slug")"

  echo
  echo "  Pick a name that's easy to remember and clearly tied to this plugin."
  echo "  Some good naming patterns:"
  printf "    • ${C_CYAN}%s${C_RESET}      ${C_DIM}(first word + 'rel' — recommended)${C_RESET}\n" "$suggested"
  printf "    • ${C_CYAN}%s${C_RESET}      ${C_DIM}(the slug itself)${C_RESET}\n" "$slug"
  printf "    • ${C_CYAN}release-%s${C_RESET}  ${C_DIM}(prefix style)${C_RESET}\n" "${slug%%-*}"
  printf "    • ${C_CYAN}r-%s${C_RESET}     ${C_DIM}(short prefix)${C_RESET}\n" "${slug%%-*}"
  echo "  Avoid common command names (git, ls, cd, etc.) and the universal 'wprel'."
  echo

  while true; do
    alias_name="$(ask "  Alias name (lowercase letters/digits/hyphens only)" "$suggested")"
    if ! [[ "$alias_name" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
      warn "  Invalid alias name: '$alias_name'"
      ask_yn "  Try again?" Y || return 0
      continue
    fi
    if alias_exists_in_profile "$alias_name" "$profile"; then
      # Smart check: if the existing alias already points to THIS plugin's
      # source folder, it's not a conflict — we're just re-running setup.
      if alias_points_to_dir "$alias_name" "$profile" "$source_dir"; then
        ok "Alias '$alias_name' is already configured for this plugin — nothing to add."
        PLUGIN_ALIAS_ADDED="$alias_name"
        return 0
      fi
      warn "  Alias '$alias_name' already exists in $profile but points to a DIFFERENT folder."
      if ! ask_yn "  Pick a different name?" Y; then
        return 0
      fi
      suggested="${alias_name}2"
      continue
    fi
    break
  done

  snippet="alias $alias_name='cd \"$source_dir\" && wprel'"

  echo
  echo "  Will append to $profile:"
  echo "      $snippet"
  echo

  if ask_yn "  Append now?" Y; then
    printf "\n# wp-release per-plugin alias for %s\n%s\n" "$slug" "$snippet" >> "$profile"
    ok "Added alias '$alias_name' to $profile"
    info "Reload your shell:    source \"$profile\""
    update_aliases_md "$alias_name" "$slug" "$source_dir"
    PLUGIN_ALIAS_ADDED="$alias_name"
  else
    info "Skipped. To install manually, paste the line above into $profile."
  fi
}

# ============================== main ===================================

clear 2>/dev/null || true
section "WordPress SVN Release — setup wizard"
echo
printf "  ${C_DIM}By Shipon Karmakar  ·  https://github.com/ShiponKarmakar/wp-svn-release${C_RESET}\n"
echo
echo "  This wizard does TWO things:"
echo "    1. Configures your machine (one time)."
echo "    2. Configures the current plugin (one time per plugin)."
echo
echo "  Re-run me anytime — for a new plugin, or to update an existing one."
echo

# ----- machine state -----
if is_machine_configured "$DEFAULT_PROFILE"; then
  ok "Machine already configured ($DEFAULT_PROFILE has WP_SVN_USER) — skipping Phase 1."
  if [[ -z "${WP_SVN_USER:-}" || -z "${WP_SVN_BASE:-}" ]]; then
    # Load values from profile into this process so Phase 2 has good defaults.
    # shellcheck disable=SC1090
    source "$DEFAULT_PROFILE" 2>/dev/null || true
  fi

  # Validate values loaded from the profile — bail out clearly if corrupt
  # rather than silently using a bad default.
  if [[ -n "${WP_SVN_BASE:-}" ]] && looks_like_url "$WP_SVN_BASE"; then
    echo
    warn "WP_SVN_BASE in $DEFAULT_PROFILE is a URL, not a local folder:"
    warn "    $WP_SVN_BASE"
    echo
    echo "  Fix it and re-run me. To clean up automatically:"
    printf "      sed -i.bak 's|^export WP_SVN_BASE=.*|export WP_SVN_BASE=\"%s/wp-svn\"|' \"%s\"\n" "$HOME" "$DEFAULT_PROFILE"
    echo "      source \"$DEFAULT_PROFILE\""
    echo
    die "Refusing to continue with invalid WP_SVN_BASE."
  fi

  ALIAS_NAME="$(read_alias_from_profile "$DEFAULT_PROFILE" || true)"
  [[ -n "$ALIAS_NAME" ]] || ALIAS_NAME="wprel"
else
  phase1_machine_setup
fi

# ----- plugin context -----
echo
if is_plugin_folder "$PWD"; then
  if [[ -f "$PWD/$SVNRELEASE_FILE" || -f "$PWD/$LEGACY_FILE" ]]; then
    if [[ -f "$PWD/$SVNRELEASE_FILE" ]]; then
      info "This plugin is already configured ($SVNRELEASE_FILE exists)."
    else
      info "This plugin has a legacy $LEGACY_FILE — re-running will migrate it."
    fi
    if ! ask_yn "Reconfigure this plugin?" N; then
      info "Skipped. Nothing changed for this plugin."
      echo
      ok "All done."
      exit 0
    fi
  fi
  phase2_plugin_setup
else
  info "Current folder doesn't look like a plugin source folder:"
  printf "      %s\n" "$PWD"
  info "(No *.php at root with a 'Plugin Name:' header.)"
  echo
  echo "  To configure a plugin, run me from its source folder:"
  echo "      cd /path/to/your/plugin/source"
  printf "      %s\n" "$0"
  echo
  ok "Machine setup is done. Run me again from a plugin folder to configure it."
fi
