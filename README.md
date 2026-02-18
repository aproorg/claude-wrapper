# claude-wrapper

Routes Claude Code through APRO's LiteLLM gateway with automatic API key management via 1Password.

## Setup

### macOS / Linux

```bash
git clone git@github.com:aproorg/claude-wrapper.git ~/code/apro/claude-wrapper

mkdir -p ~/.local/bin
ln -sf ~/code/apro/claude-wrapper/claude ~/.local/bin/claude

# Add to your .bashrc / .zshrc if ~/.local/bin isn't already on PATH:
export PATH="$HOME/.local/bin:$PATH"
```

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
  ],
  "claudeCode.claudeProcessWrapper": "/Users/USER/.local/bin/claude"
}
```

## Verify

```bash
which claude          # Should show ~/.local/bin/claude
CLAUDE_DEBUG=1 claude # Shows config being loaded
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

## Reference

<details>
<summary>How it works</summary>

The wrapper at `~/.local/bin/claude` shadows the real Claude binary. When you run `claude`:

1. Finds the real binary (via `which -a`, skipping itself)
2. Fetches `claude-env.sh` from this repo (cached for 5 minutes at `~/.cache/claude/env-remote.sh`)
3. Sources the config (sets `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, etc.)
4. Launches the real Claude Code with your arguments

On network failure, it falls back to the stale cache.

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
<summary>Alternative: env.sh bootstrap</summary>

If you prefer Claude Code's built-in env sourcing over the process wrapper:

```bash
curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node
```

This writes a bootstrap to `~/.config/claude/env.sh` which Claude Code sources on startup.

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
