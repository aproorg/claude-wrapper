# Research: Automatic Custom Header Injection

**Feature**: 003-auto-custom-headers
**Date**: 2026-02-20

## R1: ANTHROPIC_CUSTOM_HEADERS Format

**Decision**: Use `Name: Value` format (colon + space) with newline separation for multiple headers.

**Rationale**: This is the documented format per [Claude Code Settings](https://code.claude.com/docs/en/settings). The spec originally assumed comma-separated `key:value` pairs — this is incorrect. The actual format follows HTTP header conventions.

**Alternatives considered**:
- Comma-separated `key:value` — this was the initial assumption but does not match the documented behavior.
- JSON object — not supported by Claude Code.

**Format examples**:
```
# Single header
x-github-repo: claude-wrapper

# Multiple headers (newline-separated)
x-team: platform
x-github-repo: claude-wrapper
```

**Implication for FR-004 (merge logic)**: Appending to existing headers requires inserting a newline between the existing value and the new header. In bash this is `printf '%s\n%s'` or `$'...\n...'`. In PowerShell this is string interpolation with `` `n ``.

## R2: Existing Project Detection Reuse

**Decision**: Use the already-computed `$CLAUDE_PROJECT` variable (bash) / `$Project` variable (PowerShell) as the header value.

**Rationale**: Both scripts already compute the project name before the export block:
- `claude-env.sh:115` → `CLAUDE_PROJECT=$(detect_project)`
- `claudestart.ps1:190` → `$Project = Get-ClaudeProject`

The header injection should be placed **after** these lines and **before** the debug output, so the header value is available for debug printing.

**Alternatives considered**:
- Re-extract from `git remote` separately — violates FR-003 (no duplicate detection) and adds unnecessary command execution.
- Call `detect_project` again — wasteful, same result.

## R3: Placement in Scripts

**Decision**: Add header logic in the "Main" section of each script, after project detection and API key setup, before the debug output block.

**Rationale**:
- In `claude-env.sh`: after line 136 (`export CLAUDE_PROJECT`), before line 138 (debug block).
- In `claudestart.ps1`: after line 212 (`$env:CLAUDE_PROJECT = $Project`), before line 214 (debug block).

This ensures `$CLAUDE_PROJECT` / `$Project` is already set, and the debug output can include the new header.

## R4: Spec Correction Needed

**Decision**: The spec's edge case about "comma separation" and the assumption about `key:value` format need to be updated to reflect the actual `Name: Value` newline-separated format.

**Action**: Update spec.md edge cases and assumptions sections during implementation.
