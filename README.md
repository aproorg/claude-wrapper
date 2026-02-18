# claude-wrapper

Claude Code environment wrapper for APRO. Configures Claude Code to use LiteLLM as the API gateway with 1Password-managed secrets.

## Quick Install

```bash
# Clone the repo
git clone git@github.com:aproorg/claude-wrapper.git ~/code/apro/claude-wrapper

# Symlink the wrapper onto your PATH
mkdir -p ~/bin
ln -sf ~/code/apro/claude-wrapper/claude ~/bin/claude

# Ensure ~/bin is on PATH (add to .bashrc/.zshrc if not already)
export PATH="$HOME/bin:$PATH"
```

Or use the installer for the `env.sh` approach:
```bash
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node
```

## What It Does

**`claude`** — Process wrapper. Symlink this to `~/bin/claude` to shadow the real binary. It fetches and caches the remote config, sets up environment variables, then `exec`s the real Claude binary. This is the recommended approach.

**`claude-env.sh`** — Remote configuration fetched and cached by the wrapper. Contains LiteLLM endpoint, model defaults, 1Password integration, and per-project API key management.

**`env.sh`** — Alternative: thin bootstrap for `~/.config/claude/env.sh` (sourced by Claude Code on startup). Use this if you prefer the env.sh approach over the process wrapper.

**`install.js`** — Cross-platform installer for the env.sh approach (macOS, Linux, WSL, Windows).

## Architecture

```
~/bin/claude  (process wrapper, shadows real binary)
  → fetches claude-env.sh from GitHub (5-min cache TTL)
  → caches at ~/.cache/claude/env-remote.sh
  → falls back to stale cache on network failure
  → sources config (exports ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, etc.)
  → exec /opt/homebrew/bin/claude "$@"
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
