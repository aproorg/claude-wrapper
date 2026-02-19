# claude-wrapper

Route Claude Code through a [LiteLLM](https://docs.litellm.ai/) proxy with automatic API key management via [1Password CLI](https://developer.1password.com/docs/cli/).

Use this when your team runs a shared LiteLLM gateway and stores API keys in 1Password. The wrapper handles config distribution, per-project key rotation, and keeps developer machines in sync — no manual env vars to manage.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node
```

The installer:
1. Writes a process wrapper to `~/.local/bin/claude` that shadows the real binary
2. Adds `~/.local/bin` to your PATH (if not already there)
3. Prompts for your **LiteLLM base URL** and **1Password item** reference
4. Pre-fetches the team configuration

> **Non-interactive mode:** When piped without a TTY (CI, Docker), prompts are skipped and defaults are used silently.

## Verify

```bash
which claude           # Should show ~/.local/bin/claude
CLAUDE_DEBUG=1 claude  # Shows resolved config
```

## Prerequisites

- **Claude Code** installed (Homebrew, npm, or standalone)
- **[1Password CLI](https://developer.1password.com/docs/cli/get-started/)** (`op`) with CLI integration enabled
- **curl** and **git**

## Forking for Your Organization

This repo ships with defaults for the maintainers' infrastructure. To use it for your own org:

1. **Fork the repo** and update `claude-env.sh`:
   - `LITELLM_BASE_URL` — your LiteLLM gateway URL
   - `OP_ACCOUNT` — your 1Password team domain
   - `OP_ITEM` — the 1Password vault path for your API keys
2. **Update the install URL** in your fork's README to point to your raw GitHub URL
3. **Distribute** — team members run your fork's one-liner to install

Individual developers can also override any value via `~/.config/claude/local.env` without touching the shared config.

## Troubleshooting

```bash
# Clear all caches (API keys + remote config)
claude --clear-cache

# Force refresh config cache only
rm ~/.cache/claude/env-remote.sh

# Re-run installer to update local settings
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node

# Debug mode (shows resolved config + stale cache warnings)
CLAUDE_DEBUG=1 claude
```

---

## Developer Setup

If you're working on this repo, use a symlink instead of the installed wrapper:

```bash
git clone <your-fork-url> ~/claude-wrapper

mkdir -p ~/.local/bin
ln -sf ~/claude-wrapper/claude ~/.local/bin/claude

# Add to your .bashrc / .zshrc if ~/.local/bin isn't already on PATH:
export PATH="$HOME/.local/bin:$PATH"
```

Verify: `which claude` should show `~/.local/bin/claude`.

---

## Reference

<details>
<summary>How it works</summary>

The installer writes a process wrapper to `~/.local/bin/claude` that shadows the real Claude Code binary. When you run `claude`, the wrapper:

1. Finds the real binary (portable PATH iteration, skipping itself)
2. Fetches the latest team config from this repo, validates it against an integrity check, caches it for 5 minutes, falls back to stale cache on network failure
3. Sources the config to set `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, model defaults, and per-project API keys
4. Optionally sources `~/.config/claude/middleware.sh` for custom pre-launch hooks (errors are trapped with actionable messages)
5. `exec`s the real Claude Code with all original arguments

**Config override chain:** Remote defaults (`claude-env.sh`) → local overrides (`~/.config/claude/local.env`) → environment variables. Local values persist across remote config updates — the TTL-based refresh only re-fetches the remote config, never touching your local settings.

</details>

<details>
<summary>Per-project API keys</summary>

The wrapper detects the current project from the git remote (or directory name) and looks up a project-specific API key field in your 1Password item. If no project-specific field exists, it falls back to the default `API Key` field.

```
1Password item: "op://Vault/your-litellm-item"
  ├── API Key          (default fallback)
  ├── backend-api      (project-specific)
  └── customer-portal  (project-specific)
```

Override project detection: `CLAUDE_PROJECT=my-project claude`

</details>

<details>
<summary>Configuration</summary>

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_ENV_URL` | (this repo) | Override remote config URL |
| `CLAUDE_ENV_UPDATE_TTL` | `300` | Cache TTL in seconds |
| `CLAUDE_MODEL` | `claude-opus-4-6` | Override default model |
| `CLAUDE_PROJECT` | (auto-detected) | Override project name |
| `CLAUDE_DEBUG` | `0` | Enable debug output |

**Files:**

| File | Purpose |
|------|---------|
| `~/.local/bin/claude` | Process wrapper (written by installer) |
| `~/.cache/claude/env-remote.sh` | Cached remote config (auto-refreshed) |
| `~/.config/claude/local.env` | Your local overrides (never auto-modified) |
| `~/.config/claude/middleware.sh` | Optional pre-launch hook |

</details>

<details>
<summary>Local config (local.env)</summary>

The installer stores your LiteLLM URL and 1Password item in `~/.config/claude/local.env`. These values override the remote defaults and are never touched by automatic updates.

```bash
# View current settings
cat ~/.config/claude/local.env

# Re-run installer to change values (shows current as defaults)
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node
```

The file uses simple `KEY="VALUE"` format and has `0600` permissions.

</details>

<details>
<summary>Middleware</summary>

Create `~/.config/claude/middleware.sh` to run custom shell commands before Claude launches. The file is **sourced** (not executed), so it can export environment variables, modify PATH, or run setup commands.

```bash
# Example: add a custom env var
echo 'export MY_CUSTOM_VAR="hello"' > ~/.config/claude/middleware.sh

# Example: prepend to PATH
echo 'export PATH="/opt/my-tools/bin:$PATH"' > ~/.config/claude/middleware.sh
```

- The file is optional — if missing, nothing happens.
- Errors in middleware are caught and reported with an actionable message (file path + fix instructions).

</details>

<details>
<summary>Windows (PowerShell)</summary>

```powershell
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node
```

The installer downloads `claudestart.ps1`, creates a `claudestart.cmd` shim, adds the install directory to your user PATH, and prompts for your LiteLLM URL and 1Password item.

After installation, run `claudestart` to launch Claude Code with team config.

**Manual install:** Clone the repo and copy `claudestart.ps1` to a directory on your PATH. Run `Set-ExecutionPolicy RemoteSigned` first (elevated PowerShell, once).

**WSL:** Follow the macOS/Linux instructions inside your WSL shell.

</details>

<details>
<summary>VSCode integration</summary>

Add to your `settings.json`:

```json
{
  "claudeCode.environmentVariables": [
    { "name": "CLAUDE_CODE_SKIP_AUTH_LOGIN", "value": "1" }
  ],
  "claudeCode.claudeProcessWrapper": "/Users/YOU/.local/bin/claude"
}
```

</details>
