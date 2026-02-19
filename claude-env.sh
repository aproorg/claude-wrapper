#!/usr/bin/env bash
# claude-env.sh — Claude Code environment configuration
# This file is fetched and cached by the thin bootstrap at ~/.config/claude/env.sh
# Edit THIS file to change configuration for all developers.

# ============================================================================
# Configuration
# ============================================================================
LITELLM_BASE_URL="https://litellm.ai.apro.is"
OP_ACCOUNT="aproorg.1password.eu"
OP_ITEM="op://Employee/ai.apro.is litellm"

# Source local overrides (written by install.js)
_CLAUDE_LOCAL_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/claude/local.env"
if [[ -f "$_CLAUDE_LOCAL_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$_CLAUDE_LOCAL_ENV"
fi
unset _CLAUDE_LOCAL_ENV

# Models
CLAUDE_MODEL_OPUS="claude-opus-4-6"
CLAUDE_MODEL_SONNET="sonnet"
CLAUDE_MODEL_HAIKU="haiku"

# ============================================================================
# Project Detection
# ============================================================================
sanitize_name() {
  # Strip anything except alphanumeric, hyphen, underscore, dot
  echo "$1" | tr -cd 'a-zA-Z0-9_.-'
}

detect_project() {
  local raw_name=""

  if [[ -n "${CLAUDE_PROJECT:-}" ]]; then
    raw_name="$CLAUDE_PROJECT"
  else
    # Try git remote name, strip .git suffix
    raw_name=$(git remote get-url origin 2>/dev/null | sed -E 's#.*/##; s#\.git$##' || true)
    [[ -z "$raw_name" ]] && raw_name=$(basename "$PWD")
  fi

  sanitize_name "$raw_name"
}

# ============================================================================
# API Key Management
# ============================================================================
get_api_key() {
  local project="$1"
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude"
  local cache_file="$cache_dir/${project}.key"
  local cache_ttl=43200 # 12 hours

  # Create cache dir with restrictive permissions from the start
  (umask 077; mkdir -p "$cache_dir")

  # Check cache
  if [[ -f "$cache_file" ]]; then
    local cache_age
    cache_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
    if [[ $cache_age -lt $cache_ttl ]]; then
      cat "$cache_file"
      return
    fi
  fi

  local key=""

  # Try project-specific field first, then fall back to default
  key=$(op --account "$OP_ACCOUNT" read "${OP_ITEM}/${project}" 2>/dev/null || true)

  # Fall back to default "API Key" field
  if [[ -z "$key" ]]; then
    key=$(op --account "$OP_ACCOUNT" read "${OP_ITEM}/API Key" 2>/dev/null || true)

    if [[ -n "$key" && "${CLAUDE_DEBUG:-0}" == "1" ]]; then
      echo "Note: No key for project '$project', using default" >&2
    fi
  fi

  if [[ -z "$key" ]]; then
    echo "ERROR: Failed to retrieve API key from 1Password" >&2
    return 1
  fi

  # Write cache file with restrictive permissions atomically
  (umask 077; echo "$key" >"$cache_file")

  echo "$key"
}

clear_cache() {
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/claude"/*.key
  rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/claude/env-remote.sh"
  echo "Claude env + API key cache cleared" >&2
}

# ============================================================================
# Main
# ============================================================================

# Handle cache clear command
if [[ "${1:-}" == "--clear-cache" ]]; then
  clear_cache
  return 0 2>/dev/null || exit 0
fi

CLAUDE_PROJECT=$(detect_project)

# Export base configuration
export ANTHROPIC_BASE_URL="${LITELLM_BASE_URL}"
export ANTHROPIC_MODEL="${CLAUDE_MODEL:-$CLAUDE_MODEL_OPUS}"
export ANTHROPIC_SMALL_FAST_MODEL="${CLAUDE_MODEL_HAIKU}"
export CLAUDE_CODE_SUBAGENT_MODEL="${CLAUDE_MODEL_HAIKU}"

# Feature flags
export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# Get API key
if API_KEY=$(get_api_key "$CLAUDE_PROJECT"); then
  export ANTHROPIC_AUTH_TOKEN="$API_KEY"
else
  echo "Warning: Could not retrieve Claude API key" >&2
fi

# Export project for debugging
export CLAUDE_PROJECT

if [[ "${CLAUDE_DEBUG:-0}" == "1" ]]; then
  echo "Claude: project=$CLAUDE_PROJECT base=$LITELLM_BASE_URL model=$ANTHROPIC_MODEL" >&2
fi
