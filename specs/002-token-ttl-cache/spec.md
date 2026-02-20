# Feature Specification: Reliable LiteLLM Token TTL Cache

**Feature Branch**: `002-token-ttl-cache`
**Created**: 2026-02-20
**Status**: Draft
**Input**: User description: "the claude wrapper prompts 1pass each time the claude command is invoked. Implement litellm token TTL cache that works for both macos/linux and windows users without any unnecessary complexity."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Cached API Key Skips 1Password (Priority: P1)

A developer runs `claude` multiple times within a 12-hour window. After the first invocation resolves the API key from 1Password, subsequent invocations use the cached key without triggering 1Password authentication prompts or biometric confirmation.

**Why this priority**: This is the core problem — every invocation currently triggers a 1Password prompt, which slows down the developer workflow and causes frustration. Fixing this eliminates the most disruptive part of the experience.

**Independent Test**: Run `claude --version` twice in a row with `CLAUDE_DEBUG=1`. The first run may prompt 1Password; the second run must not, and the debug output should indicate the key was loaded from cache.

**Acceptance Scenarios**:

1. **Given** the developer has no cached key, **When** they run `claude`, **Then** the wrapper retrieves the key from 1Password, caches it, and launches Claude Code
2. **Given** a cached key exists and is less than 12 hours old, **When** the developer runs `claude`, **Then** the wrapper uses the cached key without contacting 1Password
3. **Given** a cached key exists but is older than 12 hours, **When** the developer runs `claude`, **Then** the wrapper fetches a fresh key from 1Password and updates the cache

---

### User Story 2 - Cache Works on macOS, Linux, and Windows (Priority: P1)

The cache mechanism works identically across macOS (bash wrapper), Linux (bash wrapper), and Windows (PowerShell wrapper). Developers on all platforms experience the same caching behavior.

**Why this priority**: The wrapper targets a cross-platform team. If caching only works on one OS, the problem persists for a portion of the team.

**Independent Test**: On each platform, run `claude --version` twice and confirm the second run does not invoke `op`. On macOS/Linux, inspect `~/.cache/claude/<project>.key`; on Windows, inspect `%LOCALAPPDATA%\claude\<project>.key`.

**Acceptance Scenarios**:

1. **Given** a macOS developer runs `claude` for the first time, **When** the key is retrieved, **Then** it is cached at `~/.cache/claude/<project>.key` with `0600` permissions
2. **Given** a Linux developer runs `claude` for the first time, **When** the key is retrieved, **Then** it is cached at `~/.cache/claude/<project>.key` with `0600` permissions
3. **Given** a Windows developer runs `claudestart` for the first time, **When** the key is retrieved, **Then** it is cached at `%LOCALAPPDATA%\claude\<project>.key`

---

### User Story 3 - Cache Clear and Manual Refresh (Priority: P2)

A developer can force-clear cached keys when they know a key has been rotated in 1Password, ensuring the next invocation fetches a fresh key.

**Why this priority**: Key rotation is an operational necessity but happens infrequently. The existing `--clear-cache` mechanism covers this, but it must also work reliably with the cache fix.

**Independent Test**: Run `claude --clear-cache`, confirm `.key` files are removed, then run `claude` and confirm a fresh key is fetched.

**Acceptance Scenarios**:

1. **Given** cached keys exist, **When** the developer runs `claude --clear-cache`, **Then** all `.key` files and the remote config cache are deleted
2. **Given** the cache was just cleared, **When** the developer runs `claude`, **Then** a fresh key is fetched from 1Password and cached

---

### Edge Cases

- What happens when the cached `.key` file exists but is empty (e.g., truncated write)?
- What happens when `stat` fails to determine the cache file's modification time (e.g., filesystem without mtime support)?
- What happens when the 1Password CLI is not authenticated (locked vault) and no cached key exists?
- What happens when two `claude` processes start simultaneously and both try to write the cache file?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The wrapper MUST check for a cached API key before invoking the `op` CLI on every invocation
- **FR-002**: The wrapper MUST use the cached key if it exists and is less than the configured TTL (default: 12 hours) old
- **FR-003**: The wrapper MUST fetch a fresh key from 1Password when no cache file exists or the cache is expired
- **FR-004**: The wrapper MUST write the cache file atomically (write to temp, then rename) to prevent corruption from concurrent writes
- **FR-005**: The wrapper MUST reject empty (0 bytes) cache files and treat them as cache misses
- **FR-006**: The wrapper MUST set restrictive file permissions on cache files (`0600` on macOS/Linux)
- **FR-007**: The cache mechanism MUST work on macOS (bash), Linux (bash), and Windows (PowerShell) using the same TTL and file-based strategy
- **FR-008**: The `--clear-cache` command MUST delete all cached API key files and the remote config cache
- **FR-009**: The cache file age calculation MUST work correctly with both macOS `stat -f %m` and Linux `stat -c %Y`

### Key Entities

- **Cache file** (`<project>.key`): Stores a single API key per project. Located in the platform cache directory. TTL: 12 hours. Permissions: `0600` (Unix).
- **Cache directory**: `~/.cache/claude/` on macOS/Linux, `%LOCALAPPDATA%\claude\` on Windows. Created with `umask 077` on Unix.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After an initial `claude` invocation that fetches from 1Password, subsequent invocations within 12 hours complete without triggering any 1Password prompt or `op` CLI call
- **SC-002**: The caching behavior is identical across macOS, Linux, and Windows — no platform-specific bugs where cache is bypassed
- **SC-003**: Developers can verify cache status via `CLAUDE_DEBUG=1 claude` — debug output clearly indicates whether the key was loaded from cache or fetched fresh
- **SC-004**: Concurrent `claude` invocations (e.g., multiple terminal tabs) do not corrupt the cache file or produce errors

## Assumptions

- The 1Password CLI (`op`) prompts for biometric/authentication on each invocation unless the session is cached by 1Password's own agent — this is expected first-invocation behavior
- The 12-hour TTL is a reasonable balance between security (key rotation) and usability (avoiding frequent prompts) — this is not user-configurable, by design
- The existing cache directory structure (`~/.cache/claude/` and `%LOCALAPPDATA%\claude\`) is correct and should not change
- File-based caching with `stat` for age checks is sufficient; no database or daemon is needed
- If the 1Password CLI is not authenticated (locked vault) and no cached key exists, the wrapper surfaces `op`'s own error — no special handling is added
- If `stat` fails on a non-standard filesystem, the fallback (`echo 0`) produces an age greater than TTL, causing a cache miss — this is safe and intentional
