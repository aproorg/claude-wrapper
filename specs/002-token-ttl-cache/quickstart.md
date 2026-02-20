# Quickstart: Verifying the Token TTL Cache Fix

## Prerequisites

- Claude Code installed
- 1Password CLI (`op`) with CLI integration enabled
- This repo checked out on branch `002-token-ttl-cache`
- Wrapper installed via `ln -sf ~/claude-wrapper/claude ~/.local/bin/claude` or the curl installer

## Verify cache hit (no 1Password prompt)

```bash
# 1. Clear cache to start fresh
claude --clear-cache

# 2. First run — will prompt 1Password (expected)
CLAUDE_DEBUG=1 claude --version
# Expected output includes: "key=fetched"

# 3. Second run — must NOT prompt 1Password
CLAUDE_DEBUG=1 claude --version
# Expected output includes: "key=cached"

# 4. Confirm cache file exists and is non-empty
ls -la ~/.cache/claude/*.key
```

## Verify empty-file guard

```bash
# 1. Create an empty cache file
: > ~/.cache/claude/$(basename $(git remote get-url origin 2>/dev/null | sed 's/.*\///;s/\.git$//')).key

# 2. Run claude — should fetch fresh key despite file existing
CLAUDE_DEBUG=1 claude --version
# Expected: "key=fetched" (not "key=cached")
```

## Verify on Windows

```powershell
# 1. Clear cache
claudestart --clear-cache

# 2. First run
$env:CLAUDE_DEBUG = "1"; claudestart --version
# Expected: key=fetched

# 3. Second run
$env:CLAUDE_DEBUG = "1"; claudestart --version
# Expected: key=cached
```
