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
# Field name used as the API-key fallback when no project-specific field exists.
# 1Password's `op read` is exact-match and case-sensitive; this default works
# for the standard apro item, but users with non-standard field names can
# override it via OP_FIELD in ~/.config/claude/local.env.
OP_FIELD="API Key"

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
  # Strip anything except alphanumeric, hyphen, underscore, dot; strip leading dots
  local name
  name=$(echo "$1" | tr -cd 'a-zA-Z0-9_.-' | sed 's/^\.*//')
  echo "${name:-unnamed}"
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
  (
    umask 077
    mkdir -p "$cache_dir"
  )

  # Check cache
  if [[ -s "$cache_file" ]]; then
    local cache_age
    cache_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
    if [[ $cache_age -lt $cache_ttl ]]; then
      [[ "${CLAUDE_DEBUG:-0}" == "1" ]] && echo "key=cached" >&2
      cat "$cache_file"
      return
    fi
  fi

  local key=""
  local errors=""
  local stderr_file
  stderr_file=$(mktemp -t claude-op-err.XXXXXX)

  # Try project-specific field first, then fall back to default. Capture op's
  # stderr to a temp file so we can surface its actual error message if both
  # attempts fail — without this, a generic "Failed to retrieve" tells users
  # nothing about whether the cause is account mismatch, expired session,
  # wrong OP_ITEM shape, etc.
  key=$(op --account "$OP_ACCOUNT" read "${OP_ITEM}/${project}" 2>"$stderr_file" || true)
  if [[ -z "$key" ]]; then
    errors+="    - ${OP_ITEM}/${project}"$'\n'
    while IFS= read -r line; do
      [[ -n "$line" ]] && errors+="        ${line}"$'\n'
    done < "$stderr_file"
  fi

  # Fall back to the configured fallback field (default "API Key", overridable
  # via OP_FIELD in local.env for users with non-standard 1Password field names)
  if [[ -z "$key" ]]; then
    : > "$stderr_file"
    key=$(op --account "$OP_ACCOUNT" read "${OP_ITEM}/${OP_FIELD}" 2>"$stderr_file" || true)
    if [[ -z "$key" ]]; then
      errors+="    - ${OP_ITEM}/${OP_FIELD}"$'\n'
      while IFS= read -r line; do
        [[ -n "$line" ]] && errors+="        ${line}"$'\n'
      done < "$stderr_file"
    elif [[ "${CLAUDE_DEBUG:-0}" == "1" ]]; then
      echo "Note: No key for project '$project', using default field '${OP_FIELD}'" >&2
    fi
  fi

  rm -f "$stderr_file"

  if [[ -z "$key" ]]; then
    {
      echo "ERROR: Failed to retrieve API key from 1Password"
      echo "  account: ${OP_ACCOUNT}"
      echo "  paths tried (with op stderr):"
      printf '%s' "$errors"
      echo "  Common fixes:"
      echo "    - Sign in if session expired:    op signin --account ${OP_ACCOUNT}"
      echo "    - List items in vault to verify path:"
      echo "                                     op item list --vault Employee --account ${OP_ACCOUNT}"
      echo "    - OP_ITEM should be op://<Vault>/<Item> (no field). Currently: ${OP_ITEM}"
      echo "      (the wrapper appends /<project> and /${OP_FIELD} to look up fields)"
      echo "    - Field name is case-sensitive (currently OP_FIELD='${OP_FIELD}')."
      echo "      Override via OP_FIELD in ~/.config/claude/local.env if your item uses"
      echo "      a different name (e.g. 'API key' with lowercase k, or 'token')."
    } >&2
    return 1
  fi

  # Write cache file with restrictive permissions atomically
  (
    umask 077
    echo "$key" >"$cache_file.tmp.$$" && mv "$cache_file.tmp.$$" "$cache_file"
  )

  [[ "${CLAUDE_DEBUG:-0}" == "1" ]] && echo "key=fetched" >&2
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
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# Get API key
if API_KEY=$(get_api_key "$CLAUDE_PROJECT"); then
  export ANTHROPIC_AUTH_TOKEN="$API_KEY"
else
  echo "Warning: Could not retrieve Claude API key" >&2
fi

# Export project for debugging
export CLAUDE_PROJECT

# Custom headers — auto-inject x-github-repo for LiteLLM per-repo attribution.
# Appends to any pre-existing ANTHROPIC_CUSTOM_HEADERS (newline-separated per
# Claude Code docs) so user-defined headers from local.env or middleware.sh
# are preserved.
_CLAUDE_HEADER="x-github-repo: ${CLAUDE_PROJECT}"
if [[ -n "${ANTHROPIC_CUSTOM_HEADERS:-}" ]]; then
  export ANTHROPIC_CUSTOM_HEADERS="${ANTHROPIC_CUSTOM_HEADERS}
${_CLAUDE_HEADER}"
else
  export ANTHROPIC_CUSTOM_HEADERS="${_CLAUDE_HEADER}"
fi
unset _CLAUDE_HEADER

if [[ "${CLAUDE_DEBUG:-0}" == "1" ]]; then
  echo "Claude: project=$CLAUDE_PROJECT base=$LITELLM_BASE_URL model=$ANTHROPIC_MODEL headers=$ANTHROPIC_CUSTOM_HEADERS" >&2
fi
