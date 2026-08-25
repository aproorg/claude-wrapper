# claude-wrapper

Route Claude Code through a [LiteLLM](https://docs.litellm.ai/) proxy with automatic API key management via [1Password CLI](https://developer.1password.com/docs/cli/).

Use this when your team runs a shared LiteLLM gateway and stores API keys in 1Password. The wrapper handles config distribution, per-project key rotation, per-repo usage attribution, and keeps developer machines in sync — no manual env vars to manage.

## Install

**macOS / Linux / WSL:**
```bash
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.ps1 | iex
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

## Testing a development branch

When testing a PR or unmerged branch, **you must `export` `CLAUDE_ENV_URL`** before running the installer. Inline `VAR=val curl ... | bash` doesn't work — env-var prefixes only set the var for the immediately-following command (`curl`), not for the `bash` subshell that runs the install script. Without the export, the installer silently falls back to `main` and downloads sibling files (the wrapper, claude-env.sh) from there.

```bash
export CLAUDE_ENV_URL="https://raw.githubusercontent.com/aproorg/claude-wrapper/<branch-name>/claude-env.sh"
curl -fsSL "https://raw.githubusercontent.com/aproorg/claude-wrapper/<branch-name>/install.sh" | bash
```

Verify the install came from the branch by checking the `[INFO] Source:` line. The installer also patches the installed wrapper so subsequent `claude` launches keep fetching from that branch.

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
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.sh | bash

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

### E2E Testing

There's no automated test suite — verify the full install-to-launch path manually.

**1. Clean slate**

```bash
# Back up your current wrapper, then remove it along with all caches.
# Use `cp -P` to preserve the symlink — plain `cp` dereferences it and
# step 9's restore would replace your dev symlink with a static byte copy.
cp -P ~/.local/bin/claude ~/.local/bin/claude.bak
rm -f ~/.local/bin/claude
rm -f ~/.cache/claude/env-remote.sh ~/.cache/claude/*.key

# Confirm only the real binary remains
which claude  # should show /opt/homebrew/bin/claude (or wherever yours lives)
```

**2. Install via curl**

```bash
CLAUDE_FORCE=1 curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.sh | bash
```

**3. Verify the wrapper shadows the real binary**

```bash
which claude           # must show ~/.local/bin/claude, NOT the real binary
CLAUDE_DEBUG=1 claude --version
# Expected: key=fetched (or key=cached), project name, base URL, model, then version
```

**4. Test cache hit (no 1Password prompt)**

```bash
CLAUDE_DEBUG=1 claude --version
# Expected: key=cached (no 1Password prompt on second run)
```

**5. Test empty-file guard**

Run this *inside the repo whose project key you want to clear* (the command
derives the project name from the current `git remote`). Also unset
`CLAUDE_PROJECT` first — if it's set in your environment (e.g. via direnv
or a parent shell), it overrides the git-based detection and the empty-file
guard won't be exercised.

```bash
unset CLAUDE_PROJECT
: > ~/.cache/claude/$(basename $(git remote get-url origin 2>/dev/null | sed 's/.*\///;s/\.git$//')).key
CLAUDE_DEBUG=1 claude --version
# Expected: key=fetched (empty cache file treated as miss)
```

**6. Test cache re-fetch**

```bash
rm ~/.cache/claude/env-remote.sh
CLAUDE_DEBUG=1 claude --version  # should re-fetch remote config
```

**7. Test env var override**

```bash
CLAUDE_MODEL="claude-sonnet-4-20250514" CLAUDE_DEBUG=1 claude --version
# model line should show claude-sonnet-4-20250514
```

**8. Test clear-cache**

```bash
claude --clear-cache
ls ~/.cache/claude/          # .key files and env-remote.sh should be gone
CLAUDE_DEBUG=1 claude --version  # should recover by re-fetching everything
```

**9. Restore**

```bash
# If you use the dev symlink:
ln -sf ~/claude-wrapper/claude ~/.local/bin/claude
# Or restore the backup:
mv ~/.local/bin/claude.bak ~/.local/bin/claude
```

| Step | What to check |
|------|---------------|
| Install | Wrapper, `local.env`, and cached remote config all written |
| `which claude` | Resolves to `~/.local/bin/claude`, not the real binary |
| Debug output | `key=fetched` or `key=cached`, correct project, base URL, model, and `headers=x-github-repo: <project>` |
| Cache hit | Second run shows `key=cached`, no 1Password prompt |
| Empty-file guard | Empty `.key` file treated as cache miss (`key=fetched`) |
| Cache re-fetch | Re-fetches after deleting `env-remote.sh` |
| Env var override | `CLAUDE_MODEL` takes priority over remote + local config |
| Clear cache | Removes all `.key` files and `env-remote.sh` |
| Recovery | Wrapper re-fetches everything and launches successfully |

---

## Reference

<details>
<summary>How it works</summary>

The installer writes a process wrapper to `~/.local/bin/claude` that shadows the real Claude Code binary. When you run `claude`, the wrapper:

1. Finds the real binary (portable PATH iteration, skipping itself)
2. Fetches the latest team config from this repo, validates it against an integrity check, caches it for 5 minutes, falls back to stale cache on network failure
3. Sources the config to set `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, model defaults, per-project API keys, and `ANTHROPIC_CUSTOM_HEADERS` (auto-injects `x-github-repo: <project>` for LiteLLM per-repo attribution)
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
<summary>Per-repo attribution (x-github-repo header)</summary>

Every request to the LiteLLM gateway is automatically tagged with an `x-github-repo: <project>` header so the gateway can attribute usage, spend, and rate-limits per repository — zero developer setup.

The value comes from the same project-detection logic used for API key lookup (`CLAUDE_PROJECT`), so a request from `~/code/your-org/backend-api` is tagged `x-github-repo: backend-api`.

If you've already set `ANTHROPIC_CUSTOM_HEADERS` (via `local.env`, shell environment, or `middleware.sh`), the auto-injected header is **appended on a new line** so your custom headers are preserved:

```
x-team: platform
x-github-repo: backend-api
```

To suppress the header on a specific project (rare — e.g., experimental scratch work you don't want attributed), strip it in your personal `~/.config/claude/middleware.sh`. The team config does not provide a built-in opt-out.

</details>

<details>
<summary>Configuration</summary>

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_ENV_URL` | (this repo) | Override remote config URL |
| `CLAUDE_ENV_UPDATE_TTL` | `300` | Cache TTL in seconds |
| `CLAUDE_MODEL` | `claude-opus-5` | Override default model |
| `CLAUDE_PROJECT` | (auto-detected) | Override project name |
| `CLAUDE_DEBUG` | `0` | Enable debug output |
| `ANTHROPIC_CUSTOM_HEADERS` | (auto-set) | Auto-injected `x-github-repo: $CLAUDE_PROJECT`. Pre-existing values preserved (header appended on new line). |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` | `1` | Suppress Claude Code's experimental beta headers and request fields. Set to `0` to lift the suppression. |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `1` | Enable the agent-teams feature. |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` | Suppress requests that aren't part of the session itself. |
| `CLAUDE_CODE_SUBAGENT_MODEL` | (unset) | Pin the model for all subagents. Left unset, a subagent uses the model its spawner requested, then its own definition's `model`, then the parent's. |
| `ENABLE_TOOL_SEARCH` | (unset) | Send MCP tool schemas on demand instead of inline. Accepts `true`, `auto`, or `auto:N`. Requires `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=0` — see [Deferred MCP tool loading](#deferred-mcp-tool-loading) below. |

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
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.sh | bash
```

The file uses simple `KEY="VALUE"` format and has `0600` permissions.

</details>

<details>
<summary id="deferred-mcp-tool-loading">Deferred MCP tool loading (tool search)</summary>

Claude Code can send MCP tool *names* up front and fetch individual schemas on demand via a `ToolSearch` tool, instead of inlining every schema in every request. It enables this automatically only when `ANTHROPIC_BASE_URL` is a first-party Anthropic host — sessions through the LiteLLM gateway fail that check, so it must be opted into explicitly.

The saving is large. Measured on this wrapper with four MCP servers connected, tool schemas were 86% of a trivial request's payload (~44K tokens); per-turn prompt tokens across a real session went from ~68,900 to ~20,700.

**Opt in** with both lines in `local.env` (`~/.config/claude/local.env`, or `%APPDATA%\claude\local.env`):

```
CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=0
ENABLE_TOOL_SEARCH=true
```

Both are required: tool search rides on the `advanced-tool-use-2025-11-20` beta, which the default suppression strips, so `ENABLE_TOOL_SEARCH` alone does nothing. Lifting the suppression also re-enables the other experimental betas — there is no per-beta switch. Besides `true`, the flag accepts `auto` and `auto:N`.

Verified against `litellm.ai.apro.is` on Bedrock: prompt-cache reads stayed monotonic with zero misses, `tool_reference` blocks round-tripped, and MCP tools resolved on demand. Works on `opus-4-7`/`opus-4-8`/`opus-5` and `sonnet-4-6`/`sonnet-5`. **`haiku-4-5` rejects** `tools[].custom.defer_loading` with HTTP 400 — so don't combine this with `CLAUDE_CODE_SUBAGENT_MODEL` pinned to haiku, or every subagent turn fails.

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

### Install

```powershell
irm https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.ps1 | iex
```

The installer:
1. Downloads `claudestart.ps1` to `%LOCALAPPDATA%\Programs\claude-wrapper\`
2. Creates a `claudestart.cmd` shim so it works from `cmd.exe` too
3. Adds the install directory to your user PATH
4. Prompts for your **LiteLLM base URL** and **1Password item** reference

> **Note:** On Windows the command is `claudestart` (not `claude`) because Windows doesn't support the same binary-shadowing trick used on macOS/Linux.

### Verify

```powershell
Get-Command claudestart           # Should show the .cmd shim
$env:CLAUDE_DEBUG = "1"; claudestart  # Shows resolved config
```

### Testing a development branch

When testing a PR or unmerged branch, you **must** set `$env:CLAUDE_ENV_URL` to the branch's `claude-env.sh` URL *before* running the installer. Without it, the installer falls back to `main` and downloads sibling files (including `claudestart.ps1`) from there — which is almost certainly not what you want when testing a branch.

```powershell
$base = "https://raw.githubusercontent.com/aproorg/claude-wrapper/<branch-name>"
$env:CLAUDE_ENV_URL = "$base/claude-env.sh"
$env:CLAUDE_FORCE = "1"  # overwrite existing wrapper without backup
irm "$base/install.ps1" | iex
```

Verify the install came from the branch by checking the `[INFO] Source:` line — it should reference your branch, not `main`. The installer also patches the installed `claudestart.ps1` so subsequent launches keep fetching from that branch.

### Prerequisites

- **Claude Code** installed (npm global install or standalone)
- **[1Password CLI](https://developer.1password.com/docs/cli/get-started/)** (`op.exe`) with CLI integration enabled
- **PowerShell 5.1+** (ships with Windows 10/11) or **PowerShell 7+**
- **git** (for project detection)

### Troubleshooting

```powershell
# Clear all caches (API keys + remote config)
claudestart --clear-cache

# Force refresh config cache only
Remove-Item "$env:LOCALAPPDATA\claude\env-remote.sh"

# Re-run installer to update local settings
irm https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.ps1 | iex

# Force reinstall wrapper (e.g. to pick up updates to claudestart.ps1)
$env:CLAUDE_FORCE = "1"; irm https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.ps1 | iex

# Debug mode
$env:CLAUDE_DEBUG = "1"; claudestart
```

### File locations

| File | Purpose |
|------|---------|
| `%LOCALAPPDATA%\Programs\claude-wrapper\claudestart.ps1` | PowerShell wrapper |
| `%LOCALAPPDATA%\Programs\claude-wrapper\claudestart.cmd` | CMD shim |
| `%LOCALAPPDATA%\claude\env-remote.sh` | Cached remote config |
| `%APPDATA%\claude\local.env` | Your local overrides |
| `%LOCALAPPDATA%\claude\<project>.key` | Cached API keys (12h TTL) |

### Manual install

If you prefer not to use the installer:

1. Run `Set-ExecutionPolicy RemoteSigned` in an elevated PowerShell (once)
2. Clone the repo and copy `claudestart.ps1` to a directory on your PATH
3. Create a `claudestart.cmd` next to it with:
   ```
   @powershell -ExecutionPolicy Bypass -File "%~dp0claudestart.ps1" %*
   ```

### WSL

Follow the macOS/Linux instructions inside your WSL shell — WSL uses the bash wrapper, not the PowerShell one.

### VSCode on Windows

Add to your `settings.json`:

```json
{
  "claudeCode.environmentVariables": [
    { "name": "CLAUDE_CODE_SKIP_AUTH_LOGIN", "value": "1" }
  ],
  "claudeCode.claudeProcessWrapper": "claudestart.cmd"
}
```

</details>

<details>
<summary>VSCode integration (macOS/Linux)</summary>

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
