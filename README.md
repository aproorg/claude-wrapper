# claude-wrapper

Claude Code environment wrapper for APRO. Configures Claude Code to use LiteLLM as the API gateway with 1Password-managed secrets.

## Prerequisites

- **Claude Code** installed ([Homebrew](https://brew.sh/), npm, or standalone)
- **[1Password CLI](https://developer.1password.com/docs/cli/get-started/)** (`op`) — for API key retrieval
  - Enable CLI integration in the 1Password Desktop app under **Settings > Developer**
- **curl** — for fetching remote config (macOS/Linux)
- **git** — for project detection (optional, falls back to directory name)

## macOS / Linux

### Option A: Process Wrapper (Recommended)

A wrapper script that shadows the real `claude` binary. It fetches the remote config, sets up environment variables, and launches the real Claude Code.

```bash
# Clone the repo
git clone git@github.com:aproorg/claude-wrapper.git ~/code/apro/claude-wrapper

# Symlink the wrapper onto your PATH
mkdir -p ~/.local/bin
ln -sf ~/code/apro/claude-wrapper/claude ~/.local/bin/claude

# Ensure ~/.local/bin is on PATH (add to .bashrc/.zshrc if not already)
export PATH="$HOME/.local/bin:$PATH"
```

Verify it works:

```bash
# Should point to your symlink, not the real binary
which claude
# => /Users/you/.local/bin/claude

# Debug mode to verify config
CLAUDE_DEBUG=1 claude
```

> **Note:** The wrapper finds the real `claude` binary automatically (via `which -a claude`), so it doesn't matter whether Claude Code was installed with Homebrew, npm, or another method.

### Option B: env.sh Bootstrap (Alternative)

If you prefer Claude Code's built-in env sourcing instead of the process wrapper:

```bash
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node
```

This writes a thin bootstrap to `~/.config/claude/env.sh` which Claude Code automatically sources on startup.

## Windows

### PowerShell Wrapper

The `claudestart.ps1` script is the Windows equivalent of the bash wrapper — it handles project detection, API key caching, and all the same environment setup.

1. **Clone the repo:**
   ```powershell
   git clone git@github.com:aproorg/claude-wrapper.git $env:USERPROFILE\code\apro\claude-wrapper
   ```

2. **Create a directory on your PATH** (e.g., `C:\Users\YOU\bin`):
   - Search for "environment" in Start and select **"Edit the system environment variables"**
   - Click **Environment Variables**
   - Select **Path** for your user, click **Edit**
   - Add the path to the directory you created

3. **Allow local scripts** (run once in an elevated PowerShell):
   ```powershell
   Set-ExecutionPolicy RemoteSigned
   ```

4. **Copy the wrapper to your PATH directory:**
   ```powershell
   Copy-Item "$env:USERPROFILE\code\apro\claude-wrapper\claudestart.ps1" "C:\Users\YOU\bin\claudestart.ps1"
   ```

5. **Run from any PowerShell:**
   ```powershell
   claudestart
   ```

> **Note:** The 1Password item path must not contain Icelandic characters. If your vault item name differs from the default, set `$OP_Item` in the script or configure the field in 1Password to match.

### Updating

To get the latest version, pull the repo and re-copy:

```powershell
cd $env:USERPROFILE\code\apro\claude-wrapper
git pull
Copy-Item claudestart.ps1 "C:\Users\YOU\bin\claudestart.ps1"
```

### WSL

If you use WSL, follow the [macOS / Linux](#macos--linux) instructions inside your WSL shell.

## VSCode Integration

Add to your VSCode `settings.json`:

```json
{
  "claudeCode.environmentVariables": [
    { "name": "CLAUDE_CODE_SKIP_AUTH_LOGIN", "value": "1" }
  ],
  "claudeCode.claudeProcessWrapper": "/Users/USER/.local/bin/claude"
}
```

- `CLAUDE_CODE_SKIP_AUTH_LOGIN` — bypasses default Anthropic authentication
- `claudeProcessWrapper` — points to the process wrapper script (update the path to match your setup)

## How It Works

### Files

| File | Platform | Purpose |
|------|----------|---------|
| `claude` | macOS/Linux | Process wrapper. Symlink onto your PATH to shadow the real binary. Fetches and caches remote config, sets env vars, then `exec`s the real Claude binary. |
| `claudestart.ps1` | Windows | PowerShell wrapper. Same features as the bash wrapper — project detection, API key caching, debug mode. Copy to a directory on your PATH. |
| `claude-env.sh` | macOS/Linux | Remote configuration fetched and cached by the bash wrapper. Contains LiteLLM endpoint, model defaults, 1Password integration, and per-project API key management. |
| `env.sh` | macOS/Linux | Alternative: thin bootstrap for `~/.config/claude/env.sh` (sourced by Claude Code on startup). |
| `install.js` | All | Cross-platform installer for the env.sh approach (macOS, Linux, WSL). |

### Architecture (Process Wrapper)

```
~/.local/bin/claude  (symlink → claude-wrapper/claude)
  → finds real claude binary via `which -a` (skips itself)
  → fetches claude-env.sh from GitHub (5-min cache TTL)
  → caches at ~/.cache/claude/env-remote.sh
  → falls back to stale cache on network failure
  → sources config (exports ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, etc.)
  → exec /opt/homebrew/bin/claude "$@"
```

### Per-Project API Keys

The wrapper auto-detects the current project from the git remote (or directory name) and looks up a project-specific API key in 1Password. If no project-specific key exists, it falls back to the default key.

```
1Password item: "op://Employee/ai.apro.is litellm"
  ├── API Key          (default, used as fallback)
  ├── backend-api      (project-specific field)
  └── customer-portal  (project-specific field)
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

**macOS / Linux:**

```bash
# Force refresh cached config
rm ~/.cache/claude/env-remote.sh

# Clear all caches (config + API keys)
source ~/.config/claude/env.sh --clear-cache

# Debug mode
CLAUDE_DEBUG=1 claude
```

**Windows (PowerShell):**

```powershell
# Force refresh cached config
Remove-Item "$env:LOCALAPPDATA\claude\env-remote.ps1"

# Clear all caches (config + API keys)
claudestart --clear-cache

# Debug mode
$env:CLAUDE_DEBUG = "1"; claudestart
```

## APRO Plugin Marketplace

APRO maintains an internal [Claude Code plugin marketplace](https://github.com/aproorg/claude-code-apro-plugin-marketplace) for sharing configurations and plugins across the team.

```
/plugins marketplace add git@github.com:aproorg/claude-code-apro-plugin-marketplace.git
```
