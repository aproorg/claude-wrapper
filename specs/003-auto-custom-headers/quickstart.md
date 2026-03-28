# Quickstart: Automatic Custom Header Injection

**Feature**: 003-auto-custom-headers

## What This Feature Does

Automatically adds an `x-github-repo` header to every Claude Code API request, identifying which repository the developer is working in. Zero configuration required.

## How It Works

After this feature ships, every Claude Code session will include the header:

```
x-github-repo: <repo-name>
```

The repo name comes from the existing project detection (git remote → fallback to directory name).

## Verification

### Unix (macOS/Linux)

```bash
# Source the config and check the variable
source ~/.config/claude/env.sh
echo "$ANTHROPIC_CUSTOM_HEADERS"
# Expected: x-github-repo: claude-wrapper  (or your repo name)
```

### Windows (PowerShell)

```powershell
# After running claudestart.ps1, check the variable
$env:ANTHROPIC_CUSTOM_HEADERS
# Expected: x-github-repo: claude-wrapper  (or your repo name)
```

### With Debug Output

```bash
CLAUDE_DEBUG=1 claude
# Look for: headers=x-github-repo: <repo-name>
```

## Adding Additional Headers

Pre-set `ANTHROPIC_CUSTOM_HEADERS` before the config runs. The auto-injected header will be appended:

```bash
export ANTHROPIC_CUSTOM_HEADERS="x-team: platform"
source ~/.config/claude/env.sh
echo "$ANTHROPIC_CUSTOM_HEADERS"
# Expected:
# x-team: platform
# x-github-repo: claude-wrapper
```

## Files Changed

| File | Change |
|------|--------|
| `claude-env.sh` | Add header export after project detection |
| `claudestart.ps1` | Add header export after project detection |
| `CLAUDE.md` | Document new env var behavior |
