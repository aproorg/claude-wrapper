# Implementation Plan: Reliable LiteLLM Token TTL Cache

**Branch**: `002-token-ttl-cache` | **Date**: 2026-02-20 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-token-ttl-cache/spec.md`

## Summary

The wrapper's `get_api_key` function (bash) and `Get-ApiKey` function (PowerShell) already implement a 12-hour TTL file cache for API keys. Investigation shows the cache **works correctly** when the `.key` file exists and is fresh. The problem is that the cache has no protection against empty/corrupt files, no debug visibility into cache hits vs. misses, and the bash implementation doesn't use atomic writes. This plan hardens the existing cache rather than adding a new caching layer.

## Technical Context

**Language/Version**: Bash (4.0+, POSIX-compatible subset) and PowerShell (5.1+/7+)
**Primary Dependencies**: `op` (1Password CLI), `curl`, `stat`, `git`
**Storage**: Flat files — `~/.cache/claude/<project>.key` (Unix), `%LOCALAPPDATA%\claude\<project>.key` (Windows)
**Testing**: Manual E2E (no test framework — see README E2E Testing section)
**Target Platform**: macOS (bash), Linux (bash), Windows (PowerShell)
**Project Type**: Single project — shell scripts, no build step
**Performance Goals**: Cache hit must add < 50ms overhead to wrapper startup
**Constraints**: Zero dependencies beyond what's already required; no daemons or background processes
**Scale/Scope**: 2 files to modify: `claude-env.sh`, `claudestart.ps1` (plus README.md for docs)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution is uninitialized (template placeholders only). No gates to evaluate. Proceeding.

## Project Structure

### Documentation (this feature)

```text
specs/002-token-ttl-cache/
├── plan.md              # This file
├── research.md          # Phase 0: root cause analysis + design decisions
├── data-model.md        # Phase 1: cache file format + lifecycle
├── quickstart.md        # Phase 1: how to verify the fix
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
claude-env.sh            # Fix: atomic writes, empty-file guard, debug cache-hit logging
claudestart.ps1          # Fix: empty-file guard, debug cache-hit logging
claude                   # No changes needed (delegates to claude-env.sh)
```

**Structure Decision**: No new files or directories. All changes are to existing scripts at the repo root. The cache directory structure (`~/.cache/claude/` and `%LOCALAPPDATA%\claude\`) is unchanged.

## Complexity Tracking

No constitution violations — no tracking needed.
