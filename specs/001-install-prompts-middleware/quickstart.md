# Quickstart: Install Prompts & Wrapper Middleware

**Branch**: `001-install-prompts-middleware` | **Date**: 2026-02-19

## What Changed

Three additions to the claude-wrapper project:

1. **Install script prompts** — `install.js` now asks for LiteLLM URL and 1Password item name during first-time setup
2. **Local config override** — User values are stored in `~/.config/claude/local.env` and take precedence over remote defaults
3. **Middleware hook** — The wrapper sources `~/.config/claude/middleware.sh` (if it exists) right before launching claude

## Files to Modify

| File | Change | Scope |
| ---- | ------ | ----- |
| `install.js` | Add `prompt()` function, interactive prompts, local.env writing | ~50 lines added |
| `claude-env.sh` | Add `source local.env` after defaults, before using values | ~5 lines added |
| `claude` | Add middleware sourcing before `exec` | ~5 lines added |

## Implementation Order

### Step 1: Local Config File Support (in `claude-env.sh`)

Add sourcing of `~/.config/claude/local.env` after the default values are set but before they're used for API key retrieval. This means even before the installer is updated, users can manually create `local.env` to override values.

### Step 2: Install Script Prompts (in `install.js`)

Add a `prompt()` function using `/dev/tty` for terminal access. After writing `env.sh`, prompt for LiteLLM URL and 1Password item name. Write responses to `local.env`.

### Step 3: Middleware Hook (in `claude`)

Add a check for `~/.config/claude/middleware.sh` and source it if present, right before the `exec "$CLAUDE_BIN" "$@"` line.

## How to Test

### Install Prompts
```bash
# First-time install (interactive)
node install.js
# → Should prompt for LiteLLM URL and 1Pass item

# Piped install (non-interactive)
curl -fsSL .../install.js | node
# → Should use defaults silently

# Reinstall (shows previous values)
node install.js
# → Should show previously stored values as defaults
```

### Local Config Override
```bash
# Verify local.env was created
cat ~/.config/claude/local.env

# Verify wrapper uses local values
CLAUDE_DEBUG=1 claude
# → Should show the URL from local.env
```

### Middleware
```bash
# Create a test middleware
echo 'export MY_TEST_VAR="hello"' > ~/.config/claude/middleware.sh

# Verify it's sourced
claude -p "echo \$MY_TEST_VAR"
```
