# LiteLLM and Claude Code

Route Claude Code through APRO's [LiteLLM](https://docs.litellm.ai/) proxy with automatic API key management via [1Password CLI](https://developer.1password.com/docs/cli/).

Use this when your team runs a shared LiteLLM gateway and stores API keys in 1Password. The wrapper handles config distribution, per-project key rotation, and keeps developer machines in sync — no manual env vars to manage.

---

# Install

```bash
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node
```

The installer prompts for your **LiteLLM base URL** and **1Password item** reference. Values are stored in `~/.config/claude/local.env` and persist across updates.

> **Non-interactive mode:** When piped without a TTY (CI, Docker), prompts are skipped and defaults are used silently.

## Verify

```bash
CLAUDE_DEBUG=1 claude  # Shows resolved config
```

`which claude` still points to your original Claude binary. This is expected — the installer writes `~/.config/claude/env.sh`, which Claude Code [sources automatically on startup](https://docs.anthropic.com/en/docs/claude-code/settings). No wrapper or PATH changes needed.

## Prerequisites

- **Claude Code** installed (Homebrew, npm, or standalone)
- **[1Password CLI](https://developer.1password.com/docs/cli/get-started/)** (`op`) with CLI integration enabled in the 1Password Desktop app under Settings → Developer
- **curl** and **git**

---

# How It Works

**Install method (env.sh bootstrap):** The installer writes a thin bootstrap to `~/.config/claude/env.sh`, which Claude Code sources on startup. It fetches the latest config from the repo, caches it for 5 minutes, and falls back to stale cache on network failure.

**Process wrapper method (alternative):** A symlink at `~/.local/bin/claude` shadows the real binary. It finds the real binary (via `which -a`), fetches and sources the config, then `exec`s the real Claude Code.

Both methods set the same environment: `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, model defaults, and per-project API keys.

**Config override chain:** Remote defaults (`claude-env.sh`) → local overrides (`~/.config/claude/local.env`) → environment variables. Local values persist across remote config updates — the TTL-based refresh only re-fetches the remote config, never touching your local settings.

---

# Per-Project API Keys

The wrapper detects the current project from the git remote (or directory name) and looks up a project-specific API key field in your 1Password item. If no project-specific field exists, it falls back to the default `API Key` field.

```
1Password item: "op://Vault/your-litellm-item"
  ├── API Key          (default fallback)
  ├── backend-api      (project-specific)
  └── customer-portal  (project-specific)
```

Override project detection: `CLAUDE_PROJECT=my-project claude`

---

# Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `CLAUDE_ENV_URL` | (this repo) | Override remote config URL |
| `CLAUDE_ENV_UPDATE_TTL` | `300` | Cache TTL in seconds |
| `CLAUDE_MODEL` | `claude-opus-4-6` | Override default model |
| `CLAUDE_PROJECT` | (auto-detected) | Override project name |
| `CLAUDE_DEBUG` | `0` | Enable debug output |

**Files:**

| File | Purpose |
| --- | --- |
| `~/.config/claude/env.sh` | Thin bootstrap (written by installer) |
| `~/.cache/claude/env-remote.sh` | Cached remote config (auto-refreshed) |
| `~/.config/claude/local.env` | Your local overrides (never auto-modified) |
| `~/.config/claude/middleware.sh` | Optional pre-launch hook (process wrapper only) |

---

# Local Config (local.env)

The installer stores your LiteLLM URL and 1Password item in `~/.config/claude/local.env`. These values override the remote defaults and are never touched by automatic updates.

```bash
# View current settings
cat ~/.config/claude/local.env

# Re-run installer to change values (shows current as defaults)
node install.js
```

The file uses simple `KEY="VALUE"` format and has `0600` permissions.

---

# Troubleshooting

```bash
# Force refresh config cache
rm ~/.cache/claude/env-remote.sh

# Re-run installer to update local settings
node install.js

# Debug mode
CLAUDE_DEBUG=1 claude
```

---

# Process Wrapper (Alternative Setup)

The installer writes an `env.sh` bootstrap that Claude Code sources automatically. If you prefer a **process wrapper** that intercepts the `claude` command (useful for middleware hooks or development on the wrapper repo):

```bash
git clone git@github.com:aproorg/claude-wrapper.git ~/claude-wrapper

mkdir -p ~/.local/bin
ln -sf ~/claude-wrapper/claude ~/.local/bin/claude

# Add to your .bashrc / .zshrc if ~/.local/bin isn't already on PATH:
export PATH="$HOME/.local/bin:$PATH"
```

Verify: `which claude` should show `~/.local/bin/claude`.

## Middleware

Create `~/.config/claude/middleware.sh` to run custom shell commands before Claude launches. The file is **sourced** (not executed), so it can export environment variables, modify PATH, or run setup commands.

```bash
# Example: add a custom env var
echo 'export MY_CUSTOM_VAR="hello"' > ~/.config/claude/middleware.sh

# Example: prepend to PATH
echo 'export PATH="/opt/my-tools/bin:$PATH"' > ~/.config/claude/middleware.sh
```

- The file is optional — if missing, nothing happens.
- Syntax errors in middleware will abort the wrapper (`set -e` is active).
- Middleware is sourced by the **process wrapper** only, not the env.sh bootstrap path.

---

# Windows (PowerShell)

1. Clone the repo: `git clone git@github.com:aproorg/claude-wrapper.git $env:USERPROFILE\claude-wrapper`
2. Create a directory on your PATH (e.g., `C:\Users\YOU\bin`) via **System Environment Variables**
3. Allow local scripts: `Set-ExecutionPolicy RemoteSigned` (elevated PowerShell, once)
4. Copy the wrapper: `Copy-Item "$env:USERPROFILE\claude-wrapper\claudestart.ps1" "C:\Users\YOU\bin\claudestart.ps1"`
5. Run: `claudestart`

**Update:** `git pull` then re-copy `claudestart.ps1`.

**WSL:** Follow the macOS/Linux instructions inside your WSL shell.

---

# VSCode Integration

Add to your `settings.json`:

```json
{
  "claudeCode.environmentVariables": [
    {
      "name": "CLAUDE_CODE_SKIP_AUTH_LOGIN",
      "value": "1"
    }
  ]
}
```

If using the process wrapper, also add:

```json
{
  "claudeCode.claudeProcessWrapper": "/Users/YOU/.local/bin/claude"
}
```

---

# Claude Code Plugins

**Extends Claude Code with custom commands, agents, hooks, Skills, and MCP servers through the plugin system.**

## What are Plugins?

- Extend Claude Code with custom functionality, commands, agents, hooks, Skills, and MCP servers
- Share configurations across projects and teams
- Install pre-built plugins from marketplaces

## [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)

- Plugin marketplaces are catalogs of available plugins
- Centralized discovery: Browse plugins from multiple sources in one place
- Version management: Track and update plugin versions automatically
- Team distribution: Share required plugins across your organization

---

# APRÓ Claude Code Marketplace

**Our internal plugin marketplace for sharing Claude Code configurations and plugins**

## Installation

```bash
/plugins marketplace add git@github.com:aproorg/claude-code-apro-plugin-marketplace.git
```

## What is it?

- Internal marketplace with curated plugins and configurations for our team
- Easy way to share and discover Claude Code setups across APRÓ
- One command to install standardized configurations
