# claude-wrapper

Claude Code environment wrapper for APRO. Configures Claude Code to use LiteLLM as the API gateway with 1Password-managed secrets.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node
```

## What It Does

1. **`env.sh`** — Thin bootstrap installed at `~/.config/claude/env.sh`. Claude Code sources this automatically on every invocation. It fetches and caches the remote configuration.

2. **`claude-env.sh`** — Remote configuration fetched by the bootstrap. Contains LiteLLM endpoint, model defaults, 1Password integration, and per-project API key management.

3. **`install.js`** — Cross-platform installer (macOS, Linux, WSL, Windows). Writes the bootstrap and pre-caches the remote config.

## Architecture

```
Claude Code start
  → sources ~/.config/claude/env.sh  (thin bootstrap)
    → fetches claude-env.sh from GitHub (5-min cache TTL)
    → caches at ~/.cache/claude/env-remote.sh
    → falls back to stale cache on network failure
    → exports ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, etc.
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_ENV_URL` | (this repo) | Override remote config URL |
| `CLAUDE_ENV_UPDATE_TTL` | `300` | Cache TTL in seconds |
| `CLAUDE_MODEL` | `claude-opus-4-6` | Override default model |
| `CLAUDE_PROJECT` | (auto-detected) | Override project name for per-project keys |
| `CLAUDE_DEBUG` | `0` | Enable debug output |

## Commands

```bash
# Force refresh cached config
rm ~/.cache/claude/env-remote.sh

# Clear all caches (config + API keys)
source ~/.config/claude/env.sh --clear-cache

# Debug mode
CLAUDE_DEBUG=1 claude
```

## Prerequisites

- [1Password CLI](https://developer.1password.com/docs/cli/get-started/) (`op`) — for API key retrieval
- `curl` — for fetching remote config
- `git` — for project detection (optional, falls back to directory name)

## VSCode Integration

```json
{
  "claudeCode.environmentVariables": [
    { "name": "CLAUDE_CODE_SKIP_AUTH_LOGIN", "value": "1" }
  ]
}
```
