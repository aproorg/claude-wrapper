#!/usr/bin/env bash
# install.sh — macOS/Linux/WSL installer for claude-wrapper
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.sh | bash
#
# Override base URL (test from a branch):
#   CLAUDE_ENV_URL=https://raw.githubusercontent.com/aproorg/claude-wrapper/<branch>/claude-env.sh \
#     curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/<branch>/install.sh | bash
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
  printf '%s\n' "${reply:-$default}"
}

read_existing() {
  local key="$1"
  [[ -f "$LOCAL_ENV" ]] || { echo ""; return; }
  sed -nE 's/^'"$key"'="(.*)"$/\1/p' "$LOCAL_ENV" | head -1
}

prompt_local_config() {
  echo >&2
  info "Configure your local connection settings:"
  echo >&2

  local current_url current_item litellm_url op_item
  current_url=$(read_existing LITELLM_BASE_URL)
  current_item=$(read_existing OP_ITEM)

  litellm_url=$(prompt_default "LiteLLM base URL" "${current_url:-https://litellm.ai.apro.is}")

  while :; do
    op_item=$(prompt_default "1Password item (op://...)" "${current_item:-op://Employee/ai.apro.is litellm}")
    [[ "$op_item" == op://* ]] && break
    warn "Must start with op:// — try again"
  done

  umask 077
  cat > "$LOCAL_ENV" <<EOF
# Local overrides — User-specific settings
# Written by install.sh, sourced by claude-env.sh
LITELLM_BASE_URL="$litellm_url"
OP_ITEM="$op_item"
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
