# claude-wrapper

Routes Claude Code through APRO's LiteLLM gateway with automatic API key management via 1Password.

## Install

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node
```

That's it. Next time you run `claude`, it will automatically use APRO's LiteLLM gateway.

### Windows

```powershell
git clone git@github.com:aproorg/claude-wrapper.git $env:USERPROFILE\code\apro\claude-wrapper
```

Then copy `claudestart.ps1` to a directory on your PATH and run `claudestart` from PowerShell. See [Windows details](#windows-details) below.

### VSCode

Add to your `settings.json`:

```json
{
  "claudeCode.environmentVariables": [
    { "name": "CLAUDE_CODE_SKIP_AUTH_LOGIN", "value": "1" }
  ]
}
```

If using the process wrapper (see [Developer setup](#developer-setup)), also add:

```json
{
  "claudeCode.claudeProcessWrapper": "/Users/USER/.local/bin/claude"
}
```

## Verify

```bash
CLAUDE_DEBUG=1 claude  # Shows config being loaded
```

## Prerequisites

- **Claude Code** installed (Homebrew, npm, or standalone)
- **[1Password CLI](https://developer.1password.com/docs/cli/get-started/)** (`op`) with CLI integration enabled in **Settings > Developer**
- **curl** and **git**

## Troubleshooting

```bash
# Force refresh config cache
rm ~/.cache/claude/env-remote.sh

# Debug mode
CLAUDE_DEBUG=1 claude
```

---

## Developer Setup

If you want to work on the wrapper itself (or prefer the process wrapper over the env.sh bootstrap):

```bash
git clone git@github.com:aproorg/claude-wrapper.git ~/code/apro/claude-wrapper

mkdir -p ~/.local/bin
ln -sf ~/code/apro/claude-wrapper/claude ~/.local/bin/claude

# Add to your .bashrc / .zshrc if ~/.local/bin isn't already on PATH:
export PATH="$HOME/.local/bin:$PATH"
```

Verify: `which claude` should show `~/.local/bin/claude`.

---

## Reference

<details>
<summary>How it works</summary>

**Install method (env.sh bootstrap):** The installer writes a thin bootstrap to `~/.config/claude/env.sh`, which Claude Code automatically sources on startup. It fetches the latest config from this repo, caches it for 5 minutes, and falls back to stale cache on network failure.

**Developer method (process wrapper):** The symlink at `~/.local/bin/claude` shadows the real binary. When you run `claude`, it finds the real binary (via `which -a`), fetches and sources the config, then launches the real Claude Code with your arguments.

Both methods set the same environment: `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, model defaults, and per-project API keys.

</details>

<details>
<summary>Per-project API keys</summary>

The wrapper detects the current project from the git remote (or directory name) and looks up a project-specific API key in 1Password. If none exists, it uses the default key.

```
1Password item: "op://Employee/ai.apro.is litellm"
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

</details>

<details>
<summary id="windows-details">Windows details</summary>

1. Clone the repo (see above)
2. Create a directory on your PATH (e.g., `C:\Users\YOU\bin`) via **System Environment Variables**
3. Allow local scripts: `Set-ExecutionPolicy RemoteSigned` (elevated PowerShell, once)
4. Copy the wrapper: `Copy-Item "$env:USERPROFILE\code\apro\claude-wrapper\claudestart.ps1" "C:\Users\YOU\bin\claudestart.ps1"`
5. Run: `claudestart`

**Update:** `git pull` then re-copy `claudestart.ps1`.

**WSL:** Follow the macOS/Linux instructions inside your WSL shell.

</details>

<details>
<summary>Plugin marketplace</summary>

```
/plugins marketplace add git@github.com:aproorg/claude-code-apro-plugin-marketplace.git
```

</details>
