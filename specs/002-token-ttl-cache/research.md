# Research: Reliable LiteLLM Token TTL Cache

## Root Cause Analysis

### Finding: Cache logic works, but has fragile edges

Live investigation on macOS confirmed:
- The `get_api_key` function in `claude-env.sh` correctly checks file age via `stat`
- When a valid `.key` file exists and is < 12h old, `op` is **not called** (verified via tracing wrapper)
- The cache file is written with `0600` permissions via `umask 077`

### Identified failure modes

| Issue | File | Severity | Description |
|-------|------|----------|-------------|
| No empty-file guard | `claude-env.sh:63-69` | High | If `.key` file exists but is empty (truncated write, disk full), `cat "$cache_file"` returns empty string, which is passed as `ANTHROPIC_AUTH_TOKEN=""` — the API call fails, user blames "cache not working" |
| Non-atomic write (bash) | `claude-env.sh:92` | Medium | `echo "$key" >"$cache_file"` is not atomic — concurrent writes can truncate. PowerShell version (`claudestart.ps1:178`) also writes directly |
| No cache-hit debug logging | Both files | Low | `CLAUDE_DEBUG=1` shows resolved config but doesn't indicate whether the key came from cache or 1Password — makes troubleshooting harder |
| `stat` fallback returns 0 | `claude-env.sh:65` | Low | If both `stat -f %m` and `stat -c %Y` fail, the fallback `echo 0` means the age calculation yields "age = now", which is > TTL, so the cache is bypassed. Rare but possible on non-standard filesystems |

## Design Decisions

### Decision 1: Add empty-file guard to cache read

**Decision**: Before using a cached key, validate that the file is non-empty (> 0 bytes). Treat empty files as cache misses.

**Rationale**: This is the highest-impact fix. An empty cache file silently passes through the current logic, producing a broken auth token. Guarding against it costs one `[ -s ]` check.

**Alternatives considered**:
- Validate key format (e.g., check length, character set): Rejected — we don't know what format LiteLLM keys use, and it couples the cache to key format
- Delete empty files on read: Rejected — unnecessary side effect; treating as cache miss is sufficient

### Decision 2: Atomic cache writes

**Decision**: Write to a temp file (`$cache_file.tmp.$$`) then `mv` to the final path. This is already the pattern used for `env-remote.sh` caching in the `claude` wrapper.

**Rationale**: `mv` on the same filesystem is atomic on POSIX. Prevents concurrent writes from producing empty/partial files. The remote config cache in `claude` already uses this pattern — consistency matters.

**Alternatives considered**:
- File locking (`flock`): Rejected — adds dependency, not available on all systems, overkill for this use case
- Write-then-verify: Rejected — adds complexity with no benefit over atomic rename

### Decision 3: Debug logging for cache hits

**Decision**: When `CLAUDE_DEBUG=1`, print whether the key was loaded from cache or fetched from 1Password.

**Rationale**: The user reported "prompts 1pass each time" — the first debugging step is `CLAUDE_DEBUG=1`, but the current output doesn't distinguish cache hit from fresh fetch. Adding one line of debug output makes this self-diagnosable.

**Alternatives considered**:
- Verbose logging (file path, age, TTL remaining): Rejected — too noisy; the existing debug output is minimal by design
- Logging to a file: Rejected — this project uses stderr for debug output, not log files
