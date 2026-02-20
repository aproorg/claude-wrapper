# Data Model: API Key Cache

## Cache File

| Attribute | Value |
|-----------|-------|
| **Path (macOS/Linux)** | `~/.cache/claude/<project>.key` |
| **Path (Windows)** | `%LOCALAPPDATA%\claude\<project>.key` |
| **Content** | Raw API key string, no newline suffix |
| **Encoding** | UTF-8 |
| **Permissions** | `0600` (Unix), default (Windows) |
| **TTL** | 43200 seconds (12 hours) |
| **Age check** | `stat -f %m` (macOS) / `stat -c %Y` (Linux) / `LastWriteTime` (PowerShell) |

## Lifecycle

```
[claude invoked]
    │
    ├── Cache file exists?
    │     ├── No  ──────────────────────────── → Fetch from 1Password
    │     └── Yes
    │           ├── File empty (0 bytes)?
    │           │     └── Yes ──────────────── → Treat as cache miss → Fetch from 1Password
    │           └── File age < TTL?
    │                 ├── Yes ──────────────── → Use cached key (cache hit)
    │                 └── No ───────────────── → Fetch from 1Password
    │
    ├── [Fetch from 1Password]
    │     ├── Write to temp file (.tmp.$$)
    │     ├── Rename temp → cache file (atomic)
    │     └── Return key
    │
    └── Export ANTHROPIC_AUTH_TOKEN
```

## Validity Rules

- Cache file MUST be non-empty (> 0 bytes) to be considered valid
- Cache file MUST have modification time within TTL window
- Cache file MUST be written atomically (temp + rename)
- Cache file content MUST NOT be validated against key format (opaque string)
