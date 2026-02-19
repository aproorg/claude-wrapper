# Implementation Plan: Install Prompts & Wrapper Middleware

**Branch**: `001-install-prompts-middleware` | **Date**: 2026-02-19 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-install-prompts-middleware/spec.md`

## Summary

Add interactive first-time setup prompts to the install script (LiteLLM base URL and 1Password item name), persist user values in a local config file that overrides remote defaults, and add a middleware hook to the wrapper script that sources an optional user-created shell script right before launching the claude binary.

## Technical Context

**Language/Version**: Node.js (install.js), Bash (wrapper and config scripts)
**Primary Dependencies**: Node.js built-ins (fs, path, os, https, readline), curl, op CLI
**Storage**: Flat files in XDG-compatible config/cache directories
**Testing**: Manual integration testing (shell scripts, no test framework)
**Target Platform**: macOS, Linux, WSL (Windows PowerShell wrapper out of scope for middleware)
**Project Type**: CLI tooling / shell scripts
**Performance Goals**: Sub-second wrapper startup (middleware adds negligible overhead)
**Constraints**: No external npm dependencies (script runs via `curl | node`), no changes to the config caching TTL mechanism
**Scale/Scope**: 3 files modified, ~60 lines added total

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution is a placeholder template with no specific constraints defined. No gates to enforce. All design decisions follow the existing project conventions (XDG paths, bash sourcing, `0600` permissions, no external dependencies).

**Post-Phase 1 re-check**: Design adds no new dependencies, no new architectural layers, no new build steps. The three changes (installer prompts, local config sourcing, middleware hook) each touch exactly one file and follow existing patterns. No violations.

## Project Structure

### Documentation (this feature)

```text
specs/001-install-prompts-middleware/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: Technical research
├── data-model.md        # Phase 1: Data model
├── quickstart.md        # Phase 1: Implementation quickstart
├── contracts/
│   ├── local-config.md  # Contract: local.env file format
│   └── middleware.md     # Contract: middleware.sh behavior
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
install.js               # Modified: add prompt(), interactive prompts, local.env writer
claude                   # Modified: add middleware.sh sourcing before exec
claude-env.sh            # Modified: add local.env sourcing after defaults
```

**Structure Decision**: No new directories or structural changes. All modifications are to existing files at the repository root. This is a CLI scripting project — the flat structure is appropriate.

## Design Decisions

### D1: Override Mechanism — Remote Config Sources Local Config

The remote config (`claude-env.sh`) sources `local.env` after setting its own defaults. This means:
- Local values override remote defaults naturally (bash variable reassignment)
- The wrapper doesn't need modification for local config (it already sources the remote config)
- The override mechanism ships to all users via the remote config auto-update

See [research.md](research.md#r3-local-config-override-mechanism) for alternatives considered.

### D2: Prompting via `/dev/tty`

The installer opens `/dev/tty` directly for readline, bypassing stdin redirection. This works for both `node install.js` and `curl | node` execution modes. If `/dev/tty` is unavailable (CI, Docker, Windows), the try/catch falls back to defaults silently.

See [research.md](research.md#r1-interactive-prompting-in-piped-nodejs-scripts) for alternatives considered.

### D3: Middleware as Single File, Not Directory

A single `middleware.sh` file rather than a `hooks/` directory with multiple files. The spec calls for one hook point (pre-exec). If multiple hooks are needed in the future, the middleware file itself can source others. YAGNI.

See [research.md](research.md#r4-middleware-file-location-and-behavior) for alternatives considered.

## Implementation Details

### Change 1: `claude-env.sh` — Local Config Sourcing (~5 lines)

After the Configuration section sets defaults for `LITELLM_BASE_URL` and `OP_ITEM`, add:

```bash
# Source local overrides (written by install.js)
_CLAUDE_LOCAL_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/claude/local.env"
if [[ -f "$_CLAUDE_LOCAL_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$_CLAUDE_LOCAL_ENV"
fi
unset _CLAUDE_LOCAL_ENV
```

**Placement**: After line 11 (after `OP_ITEM=...`), before line 13 (Models section). The local config only overrides connection settings, not model choices.

### Change 2: `install.js` — Interactive Prompts (~50 lines)

Add a `prompt()` helper function and call it during installation:

1. Add `prompt(question, defaultValue)` function using `/dev/tty` + readline
2. Add `readLocalConfig(filePath)` function to parse existing `local.env` for reinstall defaults
3. Add `writeLocalConfig(filePath, values)` function to write the file with `0600` permissions
4. In `install()`, after writing `env.sh`, call the prompt flow:
   - Read existing `local.env` if present (for defaults on reinstall)
   - Prompt for LiteLLM URL
   - Prompt for 1Password item name
   - Validate non-empty (re-prompt on empty for URL, validate `op://` prefix for item)
   - Write `local.env`

### Change 3: `claude` — Middleware Hook (~5 lines)

Before the `exec "$CLAUDE_BIN" "$@"` line, add:

```bash
# Source middleware if present
_CLAUDE_MIDDLEWARE="${XDG_CONFIG_HOME:-$HOME/.config}/claude/middleware.sh"
if [[ -f "$_CLAUDE_MIDDLEWARE" ]]; then
  # shellcheck disable=SC1090
  source "$_CLAUDE_MIDDLEWARE"
fi
```

**Placement**: After line 54 (`source "$_CACHE_FILE"`), before line 57 (`exec "$CLAUDE_BIN" "$@"`).

## Complexity Tracking

No constitutional violations to justify. All changes are minimal, follow existing patterns, and add no new dependencies or abstractions.
