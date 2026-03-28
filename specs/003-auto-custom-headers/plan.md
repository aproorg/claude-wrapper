# Implementation Plan: Automatic Custom Header Injection

**Branch**: `003-auto-custom-headers` | **Date**: 2026-02-20 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/003-auto-custom-headers/spec.md`

## Summary

Add automatic `x-github-repo` header injection to `claude-env.sh` and `claudestart.ps1`. The header value is derived from the existing project detection logic (`detect_project()` / `Get-ClaudeProject`). Pre-existing user-defined headers are preserved by appending. The `ANTHROPIC_CUSTOM_HEADERS` env var uses `Name: Value` format with newline separation per [Claude Code docs](https://code.claude.com/docs/en/settings).

## Technical Context

**Language/Version**: Bash 4.0+ (POSIX-compatible subset), PowerShell 5.1+/7+
**Primary Dependencies**: `git` (already required), `op` (1Password CLI, already required)
**Storage**: N/A — environment variables only, no persistent state
**Testing**: Manual verification via `CLAUDE_DEBUG=1` and `echo $ANTHROPIC_CUSTOM_HEADERS`
**Target Platform**: macOS, Linux (bash), Windows (PowerShell)
**Project Type**: Flat-file scripts (no src/ directory, no build step)
**Performance Goals**: Zero additional external commands or network calls
**Constraints**: Must not break existing env.sh bootstrap path; must not error on non-git directories
**Scale/Scope**: ~10 lines added per script (2 files modified, 1 file documented)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution is unconfigured (template placeholders). No project-specific gates to enforce. **PASS** — no violations.

**Post-design re-check**: Still PASS. The design adds minimal code to two existing files, introduces no new dependencies, patterns, or abstractions.

## Project Structure

### Documentation (this feature)

```text
specs/003-auto-custom-headers/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: format research findings
├── data-model.md        # Phase 1: env var flow and merge rules
├── quickstart.md        # Phase 1: verification guide
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
claude-env.sh            # Bash config — add header export (MODIFIED)
claudestart.ps1          # PowerShell config — add header export (MODIFIED)
CLAUDE.md                # Project docs — document new behavior (MODIFIED)
```

**Structure Decision**: This repo is a flat collection of scripts with no `src/` or `tests/` directory. All three template options are removed — files are modified in-place at the repository root.

## Implementation Design

### Bash (`claude-env.sh`)

Insert after `export CLAUDE_PROJECT` (line 136), before the debug block (line 138):

```bash
# Custom headers
_CLAUDE_HEADER="x-github-repo: ${CLAUDE_PROJECT}"
if [[ -n "${ANTHROPIC_CUSTOM_HEADERS:-}" ]]; then
  export ANTHROPIC_CUSTOM_HEADERS="${ANTHROPIC_CUSTOM_HEADERS}
${_CLAUDE_HEADER}"
else
  export ANTHROPIC_CUSTOM_HEADERS="${_CLAUDE_HEADER}"
fi
unset _CLAUDE_HEADER
```

Update debug line to include headers:
```bash
echo "Claude: project=$CLAUDE_PROJECT base=$LITELLM_BASE_URL model=$ANTHROPIC_MODEL headers=$ANTHROPIC_CUSTOM_HEADERS" >&2
```

### PowerShell (`claudestart.ps1`)

Insert after `$env:CLAUDE_PROJECT = $Project` (line 212), before the debug block (line 214):

```powershell
# Custom headers
$_Header = "x-github-repo: $Project"
if ($env:ANTHROPIC_CUSTOM_HEADERS) {
    $env:ANTHROPIC_CUSTOM_HEADERS = "$($env:ANTHROPIC_CUSTOM_HEADERS)`n$_Header"
} else {
    $env:ANTHROPIC_CUSTOM_HEADERS = $_Header
}
Remove-Variable _Header -ErrorAction SilentlyContinue
```

Update debug line to include headers:
```powershell
Write-Host "Claude: project=$Project base=$LiteLLM_BaseURL model=$($env:ANTHROPIC_MODEL) headers=$($env:ANTHROPIC_CUSTOM_HEADERS)" -ForegroundColor Cyan
```

### Key Design Decisions

1. **Newline literal in bash**: Uses a real newline in the string (not `\n`) for portability across bash versions. The multi-line string between quotes preserves the newline.

2. **`unset _CLAUDE_HEADER`**: Follows the existing pattern in `claude-env.sh` of cleaning up temporary variables (see `unset _CLAUDE_LOCAL_ENV` at line 19).

3. **`Remove-Variable`**: Follows the existing pattern in `claudestart.ps1` of cleaning up script-scoped variables (see line 90, 104).

4. **No deduplication**: If a user manually sets `x-github-repo` in their existing headers AND the auto-injection adds another, both will be present. At the HTTP level, the last header wins. This is acceptable and simpler than parsing/deduplicating.

5. **Always set the header**: Even in non-git directories, `CLAUDE_PROJECT` falls back to the directory name (or "unnamed"). The header is always set — the value just varies.

## Requirement Traceability

| Requirement | Implementation |
|-------------|---------------|
| FR-001: Auto-export header | `_CLAUDE_HEADER` set from `$CLAUDE_PROJECT` in both scripts |
| FR-002: Cross-platform | Identical logic in `claude-env.sh` + `claudestart.ps1` |
| FR-003: Reuse detect_project | Uses `$CLAUDE_PROJECT` / `$Project` already computed |
| FR-004: Preserve existing headers | Conditional append with newline separator |
| FR-005: No error on failure | `CLAUDE_PROJECT` always has a value (fallback to dir name) |
| FR-006: Debug output | Updated debug `echo` / `Write-Host` lines |

## Complexity Tracking

No constitution violations. No complexity justifications needed.
