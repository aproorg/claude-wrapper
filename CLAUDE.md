# claude-wrapper

Routes Claude Code through APRO's LiteLLM gateway with automatic API key management via 1Password.

## Architecture

A process wrapper shadows the real `claude` binary on PATH. When you launch `claude`, the wrapper sources team config, sets API auth via 1Password, then `exec`s the real binary.

```
~/.local/bin/claude (wrapper)
  → fetches claude-env.sh from GitHub (5-min TTL cache)
  → saves user env vars (ANTHROPIC_*) before sourcing remote config
  → sources cached config (sets ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN
    via 1Password, ANTHROPIC_CUSTOM_HEADERS with auto-injected x-github-repo)
  → restores user env vars (project .env / .envrc always wins)
  → sources optional ~/.config/claude/middleware.sh (per-user escape hatch)
  → exec's the real claude binary
```

Windows uses `claudestart.ps1` (invoked via `claudestart` after the .cmd shim) — same logic, different name because Windows can't shadow `.exe` files with a script.

## Files

| File | Purpose |
|------|---------|
| `claude` | Bash process wrapper (macOS/Linux/WSL) |
| `claudestart.ps1` | PowerShell process wrapper (Windows) |
| `claude-env.sh` | Central config: 1Password lookup, model defaults, header injection. Edit this for org-wide changes. |
| `install.sh` | Bash installer (curl-pipeable) |
| `install.ps1` | PowerShell installer (irm-pipeable) |

Config override chain: `claude-env.sh` defaults → `local.env` overrides → environment variables.

## Commands

| Command | Description |
|---------|-------------|
| `curl -fsSL .../install.sh \| bash` | Install wrapper (macOS/Linux/WSL) |
| `irm .../install.ps1 \| iex` | Install wrapper (Windows) |
| `CLAUDE_DEBUG=1 claude` | Launch with debug output showing resolved config |
| `claude --clear-cache` | Clear all cached API keys + remote config |
| `rm ~/.cache/claude/env-remote.sh` | Force re-fetch of just the remote config |

No build step, no tests, no package.json — all scripts run directly.

## Environment

**Required tools:** `curl`, `git`, `op` (1Password CLI with CLI integration enabled)

**Key env vars:**

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_ENV_URL` | (this repo's raw URL) | Override remote config source (also propagates from installer to installed wrapper) |
| `CLAUDE_ENV_UPDATE_TTL` | `300` | Cache TTL in seconds for remote config |
| `CLAUDE_MODEL` | `claude-opus-4-6` | Override default model |
| `CLAUDE_PROJECT` | (auto from git remote) | Override project name for key lookup |
| `CLAUDE_DEBUG` | `0` | Show resolved config on launch |
| `CLAUDE_FORCE` | `0` | Installer: overwrite existing wrapper without backup |
| `ANTHROPIC_CUSTOM_HEADERS` | (auto-set) | Auto-injected `x-github-repo: ${CLAUDE_PROJECT}` for LiteLLM per-repo attribution. Pre-existing values are preserved (header appended on a new line). |

**Runtime files (not in repo):**

| File | Purpose |
|------|---------|
| `~/.local/bin/claude` (or `%LOCALAPPDATA%\Programs\claude-wrapper\claudestart.ps1`) | Process wrapper (written by installer) |
| `~/.config/claude/local.env` (or `%APPDATA%\claude\local.env`) | User overrides (written by installer) |
| `~/.cache/claude/env-remote.sh` (or `%LOCALAPPDATA%\claude\env-remote.sh`) | Cached remote config (auto-refreshed every 5 min) |
| `~/.cache/claude/<project>.key` | Cached API keys (12h TTL) |
| `~/.config/claude/middleware.sh` | Optional per-user pre-launch hook (Unix only) |

## Code Style

- Bash: `set -euo pipefail`, functions prefixed with `_claude_` or `_` for cleanup via `unset`
- Security: `umask 077` before writing sensitive files, `0600` perms on keys/configs
- Cache pattern: atomic write to `.tmp.$$` then `mv` to final path
- PowerShell: PS 5.1+ compatible (no `??`, no `?.`, no inline `if` expressions); use `[Console]::Error.WriteLine()` for diagnostic output instead of `Write-Host` (more reliable across host configurations)

## Gotchas

- **`/dev/tty` prompting** — `install.sh` opens `/dev/tty` directly for interactive prompts because stdin is the piped script when run via `curl | bash`. Falls back to defaults silently if TTY unavailable.
- **`stat` cross-platform** — Cache age uses `stat -f %m` (macOS) with fallback to `stat -c %Y` (Linux). Appears in `claude-env.sh` and `claude`.
- **Wrapper self-skip** — `claude` wrapper iterates PATH and compares `realpath` to skip itself when finding the real binary. Breaks if the real claude isn't on PATH.
- **`claude-env.sh` is sourced, not executed** — Runs in the wrapper's shell context. Variables must be exported explicitly. `return` works (not `exit`).
- **Middleware is wrapper-only** — `~/.config/claude/middleware.sh` is sourced by the `claude` wrapper. Windows has no equivalent — header opt-out / provider switching must be done via env vars or by editing `claudestart.ps1` directly.
- **1Password `op` account** — Hardcoded to `aproorg.1password.eu` in `claude-env.sh` and `claudestart.ps1`. Not overridable via local.env.
- **Branch testing** — Both installers derive their base URL from `CLAUDE_ENV_URL`. Setting it before invocation makes the installer fetch *all* sibling files (wrapper, ps1, claude-env.sh) from that branch's raw URL, and patches the installed wrapper so it keeps fetching from that branch on every launch.

## Active Technologies
- Bash (4.0+, POSIX-compatible subset) and PowerShell (5.1+/7+) + `op` (1Password CLI), `curl`, `stat`, `git` (002-token-ttl-cache)
- Flat files — `~/.cache/claude/<project>.key` (Unix), `%LOCALAPPDATA%\claude\<project>.key` (Windows) (002-token-ttl-cache)
- Bash 4.0+ (POSIX-compatible subset), PowerShell 5.1+/7+ + `git` (already required), `op` (1Password CLI, already required) (003-auto-custom-headers)
- N/A — environment variables only, no persistent state (003-auto-custom-headers)

## Recent Changes
- Replaced Node-based `install.js` with native `install.sh` (bash) and `install.ps1` (PowerShell). Removed Node install-time dependency.
- 003-auto-custom-headers: Auto-inject `x-github-repo` header from `claude-env.sh` and `claudestart.ps1`.
- 002-token-ttl-cache: Added Bash (4.0+, POSIX-compatible subset) and PowerShell (5.1+/7+) + `op` (1Password CLI), `curl`, `stat`, `git`.
