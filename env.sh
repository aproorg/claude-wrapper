#!/usr/bin/env bash
# ~/.config/claude/env.sh — Thin bootstrap for Claude Code environment
#
# This file fetches and caches the full configuration from a central URL.
# DO NOT put configuration logic here — edit the remote source instead.
#
# Install:  curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node
# Update:   rm ~/.cache/claude/env-remote.sh  (or wait for TTL expiry)
# Debug:    CLAUDE_DEBUG=1 claude

# ── Remote source URL ─────────────────────────────────────────────────────────
# Override with CLAUDE_ENV_URL environment variable if needed.
CLAUDE_ENV_REMOTE_URL="${CLAUDE_ENV_URL:-https://raw.githubusercontent.com/aproorg/claude-wrapper/main/claude-env.sh}"

# ── Cache settings ────────────────────────────────────────────────────────────
_CLAUDE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude"
_CLAUDE_CACHE_FILE="$_CLAUDE_CACHE_DIR/env-remote.sh"
_CLAUDE_UPDATE_TTL="${CLAUDE_ENV_UPDATE_TTL:-300}" # check every 5 minutes

# ── Helpers ───────────────────────────────────────────────────────────────────
_claude_needs_update() {
  [[ ! -f "$_CLAUDE_CACHE_FILE" ]] && return 0
  local age
  age=$(($(date +%s) - $(stat -f %m "$_CLAUDE_CACHE_FILE" 2>/dev/null || stat -c %Y "$_CLAUDE_CACHE_FILE" 2>/dev/null || echo 0)))
  [[ $age -ge $_CLAUDE_UPDATE_TTL ]]
}

_claude_fetch_env() {
  (umask 077; mkdir -p "$_CLAUDE_CACHE_DIR")

  local tmp="$_CLAUDE_CACHE_FILE.tmp.$$"
  if (umask 077; curl -fsSL --connect-timeout 3 --max-time 10 "$CLAUDE_ENV_REMOTE_URL" -o "$tmp") 2>/dev/null; then
    mv "$tmp" "$_CLAUDE_CACHE_FILE"
  else
    rm -f "$tmp"
    # No cached copy at all — hard fail
    if [[ ! -f "$_CLAUDE_CACHE_FILE" ]]; then
      echo "ERROR: Cannot fetch Claude env from $CLAUDE_ENV_REMOTE_URL (no cache)" >&2
      return 1
    fi
    # Stale cache exists — use it silently
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
if _claude_needs_update; then
  _claude_fetch_env
fi

if [[ -f "$_CLAUDE_CACHE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$_CLAUDE_CACHE_FILE" "$@"
fi

# Cleanup helper names from the shell namespace
unset -f _claude_needs_update _claude_fetch_env
unset _CLAUDE_CACHE_DIR _CLAUDE_CACHE_FILE _CLAUDE_UPDATE_TTL
