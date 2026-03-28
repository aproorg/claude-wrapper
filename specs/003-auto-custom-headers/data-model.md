# Data Model: Automatic Custom Header Injection

**Feature**: 003-auto-custom-headers
**Date**: 2026-02-20

## Entities

This feature has no persistent data or new entities. It operates entirely through environment variables at runtime.

### Environment Variables (runtime state)

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `CLAUDE_PROJECT` | string | `detect_project()` / `Get-ClaudeProject` | Sanitized project name (already exists) |
| `ANTHROPIC_CUSTOM_HEADERS` | string | Auto-generated + user-defined | Newline-separated `Name: Value` header pairs |

### Header Value Flow

```
detect_project()  ──→  CLAUDE_PROJECT  ──→  "x-github-repo: $CLAUDE_PROJECT"
                                                     │
user-defined ANTHROPIC_CUSTOM_HEADERS (if any)  ──→  merge  ──→  final ANTHROPIC_CUSTOM_HEADERS
```

### Merge Rules

1. If `ANTHROPIC_CUSTOM_HEADERS` is empty/unset → set to `x-github-repo: <project>`
2. If `ANTHROPIC_CUSTOM_HEADERS` already has content → append `\nx-github-repo: <project>`
3. No deduplication — if user manually sets `x-github-repo`, both values will be present (last wins at HTTP level)

### Validation Rules

- `CLAUDE_PROJECT` is already sanitized by `sanitize_name()` (alphanumeric, hyphen, underscore, dot only)
- Header value is safe for HTTP headers (no CRLF injection possible due to sanitization)
- Empty/failed project detection → `CLAUDE_PROJECT` defaults to directory name or "unnamed" → header still set with fallback value
