#!/usr/bin/env bash
# install.sh — macOS/Linux/WSL installer for claude-wrapper
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.sh | bash
#
# Override base URL (test from a branch). Note: `export` is required —
# inline `VAR=value cmd1 | cmd2` only sets VAR for cmd1 (curl), not for
# the bash subshell that runs this script:
#   export CLAUDE_ENV_URL=https://raw.githubusercontent.com/aproorg/claude-wrapper/<branch>/claude-env.sh
#   curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/<branch>/install.sh | bash
#
# Options:
#   CLAUDE_FORCE=1    Overwrite existing wrapper without backup

set -euo pipefail

# ── Output helpers ──────────────────────────────────────────────────────────
if [[ -t 2 ]]; then
  _C_INFO=$'\033[34m'; _C_OK=$'\033[32m'; _C_WARN=$'\033[33m'; _C_ERR=$'\033[31m'; _C_RST=$'\033[0m'
else
  _C_INFO=""; _C_OK=""; _C_WARN=""; _C_ERR=""; _C_RST=""
fi
info()  { printf "  ${_C_INFO}[INFO]${_C_RST}  %s\n" "$1" >&2; }
ok()    { printf "  ${_C_OK}[OK]${_C_RST}    %s\n" "$1" >&2; }
warn()  { printf "  ${_C_WARN}[WARN]${_C_RST}  %s\n" "$1" >&2; }
die()   { printf "  ${_C_ERR}[ERROR]${_C_RST} %s\n" "$1" >&2; exit 1; }

# ── Configuration ───────────────────────────────────────────────────────────
DEFAULT_BASE="https://raw.githubusercontent.com/aproorg/claude-wrapper/main"

# Derive base URL from CLAUDE_ENV_URL (so branch installs propagate)
if [[ -n "${CLAUDE_ENV_URL:-}" ]]; then
  REMOTE_ENV_URL="$CLAUDE_ENV_URL"
  BASE_URL="${CLAUDE_ENV_URL%/claude-env.sh}"
else
  BASE_URL="$DEFAULT_BASE"
  REMOTE_ENV_URL="$BASE_URL/claude-env.sh"
fi

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude"
WRAPPER_PATH="$BIN_DIR/claude"
LOCAL_ENV="$CONFIG_DIR/local.env"
REMOTE_CACHE="$CACHE_DIR/env-remote.sh"

# ── Prerequisites ───────────────────────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }

check_prerequisites() {
  have curl || die "curl is required"
  have claude || die "Claude Code must be installed first (brew install claude-code, or npm install -g @anthropic-ai/claude-code)"
  have op   || warn "1Password CLI (op) not found — API key management will not work. Install: https://developer.1password.com/docs/cli/get-started/"
  have git  || warn "git not found — project detection will fall back to directory name"
}

# ── Shell profile (for PATH) ────────────────────────────────────────────────
detect_profile() {
  case "${SHELL:-}" in
    */zsh) echo "$HOME/.zshrc" ;;
    */bash)
      if [[ -f "$HOME/.bashrc" ]]; then echo "$HOME/.bashrc"
      else echo "$HOME/.bash_profile"; fi ;;
    *) echo "$HOME/.profile" ;;
  esac
}

ensure_on_path() {
  case ":$PATH:" in
    *":$BIN_DIR:"*) ok "$BIN_DIR is already on PATH"; return ;;
  esac
  local profile
  profile=$(detect_profile)
  if [[ -f "$profile" ]] && grep -q "$BIN_DIR" "$profile" 2>/dev/null; then
    warn "$BIN_DIR is in $profile but not on current PATH — restart your shell"
    return
  fi
  printf '\nexport PATH="%s:$PATH"\n' "$BIN_DIR" >> "$profile"
  ok "Added $BIN_DIR to PATH in $profile"
  warn "Restart your shell or run: source $profile"
}

# ── Interactive prompts (via /dev/tty for curl-pipe compatibility) ──────────
prompt_default() {
  local question="$1" default="$2" reply=""
  # Open /dev/tty as fd 3 inside a brace block so any "Device not configured"
  # error stays silent — falls through to the default cleanly in CI/Docker.
  if { exec 3<>/dev/tty; } 2>/dev/null; then
    printf "  %s [%s]: " "$question" "$default" >&3
    IFS= read -r reply <&3 || reply=""
    exec 3<&-
  fi
  reply="${reply:-$default}"
  # Strip surrounding matched quotes — copy-pasted values from docs/secret
  # managers often arrive with quote chars that break naive validation.
  if [[ "$reply" == \"*\" || "$reply" == \'*\' ]]; then
    reply="${reply:1:${#reply}-2}"
  fi
  printf '%s\n' "$reply"
}

read_existing() {
  local key="$1"
  [[ -f "$LOCAL_ENV" ]] || { echo ""; return; }
  sed -nE 's/^'"$key"'="(.*)"$/\1/p' "$LOCAL_ENV" | head -1
}

# Try to enumerate field labels for an OP_ITEM. Returns one label per line on
# stdout, empty if op fails (not signed in, item doesn't exist, op missing).
# Pure grep+sed JSON parse: 1Password field labels are plain text without
# escape sequences, so no need for jq as a hard dependency.
#
# Note: `op item get` does NOT accept the op://Vault/Item syntax — that's
# only valid for `op read`. We parse the OP_ITEM into vault + item name.
list_op_fields() {
  local op_item="$1"
  local account="${OP_ACCOUNT:-aproorg.1password.eu}"
  have op || return 0

  local stripped="${op_item#op://}"
  local vault="${stripped%%/*}"
  local item="${stripped#*/}"
  [[ -n "$vault" && -n "$item" && "$vault" != "$item" ]] || return 0

  # Scope to the "fields" array (URLs and other sections also have "label" keys
  # we don't want). Pretty-printed JSON has whitespace after colons, so the
  # regex tolerates it. Plain text labels — no escape sequences to worry about.
  op --account "$account" item get "$item" --vault "$vault" --format json 2>/dev/null \
    | awk '/"fields":[[:space:]]*\[/{flag=1} flag' \
    | grep -oE '"label":[[:space:]]*"[^"]*"' \
    | sed -E 's/^"label":[[:space:]]*"//; s/"$//'
}

prompt_op_field() {
  local op_item="$1"
  local default_field="$2"
  local fields field_array=()

  fields=$(list_op_fields "$op_item")
  if [[ -z "$fields" ]]; then
    warn "Could not enumerate fields for $op_item (op missing, not signed in, or item not found)"
    while :; do
      local reply
      reply=$(prompt_default "1Password field name (case-sensitive)" "$default_field")
      if [[ "$reply" == op://* ]]; then
        warn "Field name is just the label (e.g. 'API Key'), not a full op:// path"
        continue
      fi
      printf '%s\n' "$reply"
      return
    done
  fi

  echo >&2
  info "Fields available in $op_item:"
  local i=1
  while IFS= read -r field; do
    [[ -z "$field" ]] && continue
    field_array+=("$field")
    printf "    [%d] %s\n" "$i" "$field" >&2
    i=$((i+1))
  done <<< "$fields"
  echo >&2

  while :; do
    local reply
    reply=$(prompt_default "1Password field name (or number)" "$default_field")
    if [[ "$reply" =~ ^[0-9]+$ ]]; then
      local idx=$((reply - 1))
      if [[ $idx -ge 0 && $idx -lt ${#field_array[@]} ]]; then
        printf '%s\n' "${field_array[$idx]}"
        return
      fi
      warn "Number out of range — try again"
      continue
    fi
    if [[ "$reply" == op://* ]]; then
      warn "Field name is just the label (e.g. 'API Key'), not a full op:// path"
      continue
    fi
    printf '%s\n' "$reply"
    return
  done
}

prompt_local_config() {
  echo >&2
  info "Configure your local connection settings:"
  echo >&2

  local current_url current_item current_field litellm_url op_item op_field
  current_url=$(read_existing LITELLM_BASE_URL)
  current_item=$(read_existing OP_ITEM)
  current_field=$(read_existing OP_FIELD)

  # Migrate legacy OP_ITEM that included the field as a path segment.
  # Pre-#13, the field was baked into OP_ITEM (e.g. op://V/Item/API Key).
  # Post-#13, OP_FIELD is separate and the wrapper appends it itself, so a
  # legacy value would yield op://V/Item/API Key/API Key on lookup.
  if [[ -n "$current_item" ]]; then
    local stripped_item="${current_item#op://}"
    local -a segs=()
    IFS='/' read -ra segs <<< "$stripped_item"
    if (( ${#segs[@]} > 2 )); then
      local migrated_item="op://${segs[0]}/${segs[1]}"
      local migrated_field="${stripped_item#${segs[0]}/${segs[1]}/}"
      warn "Detected legacy OP_ITEM with field appended; migrating:"
      warn "  $current_item"
      warn "  → OP_ITEM=$migrated_item"
      warn "  → OP_FIELD=$migrated_field"
      current_item="$migrated_item"
      current_field="$migrated_field"
    fi
  fi

  litellm_url=$(prompt_default "LiteLLM base URL" "${current_url:-https://litellm.ai.apro.is}")

  while :; do
    op_item=$(prompt_default "1Password item (op://Vault/Item, no field)" "${current_item:-op://Employee/ai.apro.is litellm}")
    if [[ "$op_item" != op://* ]]; then
      warn "Must start with op:// — try again"
      continue
    fi
    local _validate_stripped="${op_item#op://}"
    local -a _validate_segs=()
    IFS='/' read -ra _validate_segs <<< "$_validate_stripped"
    if (( ${#_validate_segs[@]} > 2 )); then
      local _hint_field="${_validate_stripped#${_validate_segs[0]}/${_validate_segs[1]}/}"
      warn "OP_ITEM should be just op://Vault/Item — you included the field in the path."
      warn "  Use op://${_validate_segs[0]}/${_validate_segs[1]} here, then '${_hint_field}' in the next prompt."
      continue
    fi
    if (( ${#_validate_segs[@]} < 2 )) || [[ -z "${_validate_segs[0]}" || -z "${_validate_segs[1]}" ]]; then
      warn "OP_ITEM needs both Vault and Item — got '$op_item'"
      continue
    fi
    break
  done

  op_field=$(prompt_op_field "$op_item" "${current_field:-API Key}")

  umask 077
  cat > "$LOCAL_ENV" <<EOF
# Local overrides — User-specific settings
# Written by install.sh, sourced by claude-env.sh
LITELLM_BASE_URL="$litellm_url"
OP_ITEM="$op_item"
OP_FIELD="$op_field"
EOF
  ok "Wrote $LOCAL_ENV"
}

# ── Fetch + patch the wrapper script ────────────────────────────────────────
fetch_wrapper() {
  # Bake the chosen REMOTE_ENV_URL into the wrapper as the default. This
  # ensures that a wrapper installed from a branch URL keeps fetching from
  # that branch, without the user having to re-export CLAUDE_ENV_URL.
  local default_line='CLAUDE_ENV_REMOTE_URL="${CLAUDE_ENV_URL:-https://raw.githubusercontent.com/aproorg/claude-wrapper/main/claude-env.sh}"'
  local patched_line="CLAUDE_ENV_REMOTE_URL=\"\${CLAUDE_ENV_URL:-${REMOTE_ENV_URL}}\""
  curl -fsSL --connect-timeout 10 --max-time 30 "${BASE_URL}/claude" \
    | awk -v from="$default_line" -v to="$patched_line" \
        '{ if ($0 == from) print to; else print $0 }'
}

backup_existing() {
  [[ -e "$WRAPPER_PATH" || -L "$WRAPPER_PATH" ]] || return 0
  if [[ "${CLAUDE_FORCE:-0}" == "1" ]]; then
    rm -f "$WRAPPER_PATH"
    info "Removed existing wrapper (CLAUDE_FORCE=1)"
    return 0
  fi
  if [[ -L "$WRAPPER_PATH" ]]; then
    info "Replacing symlink $WRAPPER_PATH → $(readlink "$WRAPPER_PATH")"
    rm -f "$WRAPPER_PATH"
  else
    local backup="$WRAPPER_PATH.backup.$(date +%s)"
    cp -P "$WRAPPER_PATH" "$backup"
    info "Backed up existing wrapper to $backup"
    rm -f "$WRAPPER_PATH"
  fi
}

# ── Remove other claude-wrappers on PATH ────────────────────────────────────
# A second wrapper earlier on PATH will be invoked first when the user types
# `claude`. If it's an older version with stale config (different OP_ITEM, old
# remote URL, etc.), it'll print error messages on every launch even though
# claude eventually works because it exec's into the next claude on PATH.
# Real claude binaries don't reference CLAUDE_ENV_REMOTE_URL, so that string
# is a reliable signature for our wrappers (current or legacy).
#
# Default behavior: prompt the user to remove each one (default Y). With
# CLAUDE_FORCE=1, remove without prompting. Each removed wrapper is backed
# up next to itself with a .legacy.backup.<timestamp> suffix.
remove_other_wrappers() {
  local IFS=:
  local found=()
  local self
  self=$(_realpath "$WRAPPER_PATH" 2>/dev/null || echo "")
  for dir in $PATH; do
    local candidate="$dir/claude"
    [[ -f "$candidate" && -x "$candidate" ]] || continue
    [[ "$(_realpath "$candidate" 2>/dev/null)" == "$self" ]] && continue
    if grep -q "CLAUDE_ENV_REMOTE_URL=" "$candidate" 2>/dev/null; then
      found+=("$candidate")
    fi
  done
  [[ ${#found[@]} -eq 0 ]] && return 0

  echo >&2
  warn "Found other claude-wrapper installs on PATH that will take precedence"
  warn "over $WRAPPER_PATH. They print spurious 1Password / config errors on"
  warn "every launch even though claude itself works (because they exec into"
  warn "the next claude on PATH)."
  echo >&2

  local f
  for f in "${found[@]}"; do
    local should_remove=""
    if [[ "${CLAUDE_FORCE:-0}" == "1" ]]; then
      should_remove="y"
    elif { exec 3<>/dev/tty; } 2>/dev/null; then
      printf "  Remove legacy wrapper at %s? [Y/n]: " "$f" >&3
      IFS= read -r should_remove <&3 || should_remove=""
      exec 3<&-
    else
      # No TTY and no CLAUDE_FORCE — leave it alone with explicit instructions.
      warn "Skipping $f (no TTY, set CLAUDE_FORCE=1 to auto-remove)"
      warn "  Manual: rm $f"
      continue
    fi

    if [[ -z "$should_remove" || "$should_remove" =~ ^[Yy] ]]; then
      local backup="$f.legacy.backup.$(date +%s)"
      cp -P "$f" "$backup" 2>/dev/null || true
      if rm -f "$f"; then
        ok "Removed $f (backup: $backup)"
      else
        warn "Could not remove $f — may need sudo. Manual: sudo rm $f"
      fi
    else
      warn "Kept $f — claude will continue to invoke it instead of $WRAPPER_PATH"
    fi
  done
}

# Portable realpath (macOS lacks readlink -f). Mirrors the wrapper's helper.
_realpath() {
  local p="$1"
  [[ -e "$p" ]] || return 1
  while [[ -L "$p" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    [[ "$p" != /* ]] && p="$dir/$p"
  done
  cd -P "$(dirname "$p")" && echo "$(pwd)/$(basename "$p")"
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
  echo >&2
  echo "  Claude Code Environment Installer" >&2
  echo "  $(printf '─%.0s' {1..35})" >&2
  echo >&2

  check_prerequisites

  info "Wrapper:  $WRAPPER_PATH"
  info "Source:   $BASE_URL"

  mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$CACHE_DIR"
  chmod 700 "$CACHE_DIR" 2>/dev/null || true

  backup_existing

  info "Downloading process wrapper..."
  if fetch_wrapper > "$WRAPPER_PATH.tmp"; then
    chmod +x "$WRAPPER_PATH.tmp"
    mv "$WRAPPER_PATH.tmp" "$WRAPPER_PATH"
    ok "Wrote $WRAPPER_PATH"
  else
    rm -f "$WRAPPER_PATH.tmp"
    die "Failed to download wrapper from ${BASE_URL}/claude"
  fi

  ensure_on_path

  info "Fetching remote configuration..."
  if curl -fsSL --connect-timeout 3 --max-time 10 "$REMOTE_ENV_URL" -o "$REMOTE_CACHE.tmp"; then
    chmod 600 "$REMOTE_CACHE.tmp"
    mv "$REMOTE_CACHE.tmp" "$REMOTE_CACHE"
    ok "Remote configuration cached"
  else
    rm -f "$REMOTE_CACHE.tmp"
    warn "Could not pre-fetch remote config (will be fetched on first launch)"
  fi

  prompt_local_config

  remove_other_wrappers

  echo >&2
  ok "Installation complete!"
  cat <<EOF >&2

  The wrapper at $WRAPPER_PATH shadows the real binary,
  injects your team config, and forwards all arguments.

  Commands:
    Verify:         which claude  (should show $WRAPPER_PATH)
    Debug:          CLAUDE_DEBUG=1 claude
    Force refresh:  rm $REMOTE_CACHE

EOF
}

main "$@"
