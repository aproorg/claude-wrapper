# claude-wrapper

Routes Claude Code through APRO's LiteLLM gateway with automatic API key management via 1Password.

## Architecture

Two independent paths to configure Claude Code's environment — both set the same env vars:

```
install.js          → writes ~/.config/claude/env.sh (thin bootstrap)
                      writes ~/.config/claude/local.env (user settings)
                      Claude Code auto-sources env.sh on startup

claude (wrapper)    → process wrapper, symlinked to ~/.local/bin/claude
                      shadows the real binary, sources config, then exec's it
```

```
claude-env.sh       # Remote config (fetched + cached by both paths)
env.sh              # Thin bootstrap template (written by install.js)
claude              # Process wrapper (bash, for developer setup)
claudestart.ps1     # Windows PowerShell equivalent of claude wrapper
install.js          # One-line curl installer (Node.js, zero deps)
```

Config override chain: `claude-env.sh` defaults → `local.env` overrides → env var overrides.

## Commands

| Command | Description |
|---------|-------------|
| `node install.js` | Run installer (prompts for LiteLLM URL + 1Password item) |
| `CLAUDE_DEBUG=1 claude` | Launch with debug output showing resolved config |
| `rm ~/.cache/claude/env-remote.sh` | Force re-fetch remote config on next launch |
| `source ~/.config/claude/env.sh --clear-cache` | Clear all cached keys + remote config |

No build step, no tests, no package.json — all scripts run directly.

## Key Files

- `claude-env.sh` — Central config: project detection, 1Password key lookup, model defaults. This is the file to edit for org-wide config changes.
- `install.js` — Curl-pipeable installer. Writes env.sh bootstrap + local.env. Uses `/dev/tty` for prompts (see Gotchas).
- `claude` — Bash process wrapper. Finds real binary via `which -a`, skips itself, sources config, then `exec`s.
- `local.env` — User's `LITELLM_BASE_URL` and `OP_ITEM` overrides. Written by installer, never auto-modified. `0600` perms.

## Environment

**Required tools:** `curl`, `op` (1Password CLI with CLI integration enabled), `git`

**Key env vars:**

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_ENV_URL` | (this repo's raw URL) | Override remote config source |
| `CLAUDE_ENV_UPDATE_TTL` | `300` | Cache TTL in seconds for remote config |
| `CLAUDE_MODEL` | `claude-opus-4-6` | Override default model |
| `CLAUDE_PROJECT` | (auto from git remote) | Override project name for key lookup |
| `CLAUDE_DEBUG` | `0` | Show resolved config on launch |
| `CLAUDE_FORCE` | `0` | Installer: overwrite existing env.sh without prompting |

**Runtime files (not in repo):**

| File | Purpose |
|------|---------|
| `~/.config/claude/env.sh` | Thin bootstrap (written by installer) |
| `~/.config/claude/local.env` | User overrides (written by installer) |
| `~/.cache/claude/env-remote.sh` | Cached remote config (auto-refreshed) |
| `~/.cache/claude/<project>.key` | Cached API keys (12h TTL) |
| `~/.config/claude/middleware.sh` | Optional pre-launch hook (process wrapper only) |

## Code Style

- Bash: `set -euo pipefail`, functions prefixed with `_claude_` or `_` for cleanup via `unset`
- Security: `umask 077` before writing sensitive files, `0600` perms on keys/configs
- Cache pattern: atomic write to `.tmp.$$` then `mv` to final path
- Node: vanilla Node.js with zero dependencies (must work via `curl | node`)

## Gotchas

- **`/dev/tty` prompting** — `install.js` opens `/dev/tty` directly for interactive prompts because stdin is the piped script when run via `curl | node`. Falls back to defaults silently if TTY unavailable.
- **`stat` cross-platform** — Cache age uses `stat -f %m` (macOS) with fallback to `stat -c %Y` (Linux). Both appear in `claude-env.sh`, `claude`, and `env.sh`.
- **Wrapper self-skip** — `claude` wrapper uses `which -a claude` and compares `readlink -f` to skip itself when finding the real binary. Breaks if the real claude isn't on PATH.
- **`env.sh` is sourced, not executed** — Both `env.sh` and `claude-env.sh` run in the caller's shell context. Variables must be exported explicitly. `return` works (not `exit`).
- **Middleware is process-wrapper only** — `~/.config/claude/middleware.sh` is sourced by the `claude` wrapper but NOT by the env.sh bootstrap path. Users of the bootstrap path don't get middleware.
- **Key cache files** — `.key` files in `~/.cache/claude/` are gitignored in this repo but the pattern also matches the runtime cache. The 12h TTL is in `claude-env.sh`, not configurable via env var.
- **1Password `op` account** — Hardcoded to `aproorg.1password.eu` in `claude-env.sh` and `claudestart.ps1`. Not overridable via local.env.
