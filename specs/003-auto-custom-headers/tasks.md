# Tasks: Automatic Custom Header Injection

**Input**: Design documents from `/specs/003-auto-custom-headers/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: No tests requested — this project has no test framework. Manual verification via `CLAUDE_DEBUG=1` and `echo $ANTHROPIC_CUSTOM_HEADERS`.

**Organization**: Tasks are grouped by user story. US3 (Header Extensibility) has no separate implementation tasks — the merge logic is built into US1/US2 by design.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This repo is a flat collection of scripts at the repository root — no `src/` or `tests/` directory.

---

## Phase 1: Setup

**Purpose**: No setup needed — flat-file scripts, no build system, no dependencies to install.

(No tasks in this phase.)

---

## Phase 2: Foundational

**Purpose**: No foundational work needed — header injection reuses existing `detect_project()` / `Get-ClaudeProject` infrastructure already present in both scripts.

(No tasks in this phase.)

---

## Phase 3: User Story 1 - Automatic Repo Identification (Priority: P1) :dart: MVP

**Goal**: Every Claude Code session launched from a git repo automatically includes an `x-github-repo` header in `ANTHROPIC_CUSTOM_HEADERS`, derived from the existing project detection.

**Independent Test**: `source claude-env.sh && echo "$ANTHROPIC_CUSTOM_HEADERS"` — should output `x-github-repo: <repo-name>`.

### Implementation for User Story 1

- [ ] T001 [US1] Add header injection with merge logic after `export CLAUDE_PROJECT` (line 136) in claude-env.sh — construct `_CLAUDE_HEADER` from `$CLAUDE_PROJECT`, conditionally append to or set `ANTHROPIC_CUSTOM_HEADERS`, then `unset _CLAUDE_HEADER`

**Checkpoint**: After T001, bash users in a git repo see `x-github-repo: <name>` in `$ANTHROPIC_CUSTOM_HEADERS`. Non-git directories use fallback name. Pre-existing headers are preserved (FR-004).

---

## Phase 4: User Story 2 - Cross-Platform Parity (Priority: P1)

**Goal**: The same header injection works on Windows via PowerShell, producing identical output format.

**Independent Test**: Run `claudestart.ps1` then `$env:ANTHROPIC_CUSTOM_HEADERS` — should output `x-github-repo: <repo-name>` matching the bash output.

### Implementation for User Story 2

- [ ] T002 [US2] Add header injection with merge logic after `$env:CLAUDE_PROJECT = $Project` (line 212) in claudestart.ps1 — construct `$_Header` from `$Project`, conditionally append to or set `$env:ANTHROPIC_CUSTOM_HEADERS`, then `Remove-Variable _Header`

**Checkpoint**: After T002, both platforms produce identical `x-github-repo: <name>` headers for the same repo. US1 and US2 together satisfy FR-001, FR-002, FR-003, FR-004, FR-005.

---

## Phase 5: User Story 3 - Header Extensibility (Priority: P2)

**Goal**: Pre-existing `ANTHROPIC_CUSTOM_HEADERS` values (from `local.env`, env vars, or `middleware.sh`) are preserved alongside the auto-injected header.

**Independent Test**: `export ANTHROPIC_CUSTOM_HEADERS="x-team: platform" && source claude-env.sh && echo "$ANTHROPIC_CUSTOM_HEADERS"` — should show both headers separated by a newline.

### Implementation for User Story 3

> **Note**: The merge logic (conditional append with newline separator) is already implemented in T001 and T002. The `if [[ -n "${ANTHROPIC_CUSTOM_HEADERS:-}" ]]` / `if ($env:ANTHROPIC_CUSTOM_HEADERS)` branches handle the "existing headers" case by appending rather than overwriting. No additional code is needed for this story — it is satisfied by the implementation design of US1/US2.

(No additional tasks — covered by T001 and T002.)

**Checkpoint**: Pre-setting `ANTHROPIC_CUSTOM_HEADERS` before running either script preserves the original value with the auto-injected header appended on a new line.

---

## Phase 6: User Story 4 - Debug Visibility (Priority: P3)

**Goal**: When `CLAUDE_DEBUG=1`, the resolved custom headers appear in the debug output alongside project, base URL, and model.

**Independent Test**: `CLAUDE_DEBUG=1 source claude-env.sh` — stderr should include `headers=x-github-repo: <name>`.

### Implementation for User Story 4

- [ ] T003 [P] [US4] Update debug echo line (line 139) in claude-env.sh to append `headers=$ANTHROPIC_CUSTOM_HEADERS` to the existing debug output
- [ ] T004 [P] [US4] Update debug Write-Host line (line 215) in claudestart.ps1 to append `headers=$($env:ANTHROPIC_CUSTOM_HEADERS)` to the existing debug output

**Checkpoint**: Both platforms show the resolved headers in debug mode. FR-006 satisfied.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates and end-to-end verification.

- [ ] T005 [P] Update CLAUDE.md to document `ANTHROPIC_CUSTOM_HEADERS` in the "Key env vars" table and add a note about auto-injection behavior
- [ ] T006 Run quickstart.md verification steps on both platforms to confirm all acceptance scenarios pass

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Skipped — no setup needed
- **Foundational (Phase 2)**: Skipped — no shared infrastructure to create
- **US1 (Phase 3)**: No dependencies — can start immediately
- **US2 (Phase 4)**: No dependency on US1 (different file) — can run in parallel with Phase 3
- **US3 (Phase 5)**: Covered by T001/T002 — no separate phase execution needed
- **US4 (Phase 6)**: Depends on T001 and T002 (header must be set before debug line references it)
- **Polish (Phase 7)**: Depends on T001–T004 being complete

### User Story Dependencies

- **US1 (P1)**: Independent — touches only claude-env.sh
- **US2 (P1)**: Independent — touches only claudestart.ps1
- **US3 (P2)**: No separate tasks — merge logic built into US1/US2 implementation
- **US4 (P3)**: Depends on US1 and US2 (debug line must reference the header variable that T001/T002 create)

### Parallel Opportunities

- **T001 and T002**: Different files, no dependencies — can run in parallel
- **T003 and T004**: Different files, no dependencies — can run in parallel (after T001/T002)
- **T005**: Independent of T003/T004 — can run in parallel with Phase 6

---

## Parallel Example: US1 + US2

```text
# These touch different files and can run simultaneously:
T001 [US1] Header injection in claude-env.sh
T002 [US2] Header injection in claudestart.ps1

# Then, after both complete:
T003 [US4] Debug line update in claude-env.sh
T004 [US4] Debug line update in claudestart.ps1
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001 (header injection in claude-env.sh)
2. **STOP and VALIDATE**: `source claude-env.sh && echo "$ANTHROPIC_CUSTOM_HEADERS"`
3. Confirm header appears with correct repo name
4. This alone delivers value for Unix users

### Incremental Delivery

1. T001 → Unix header injection works (MVP)
2. T002 → Windows parity achieved
3. T003 + T004 → Debug visibility on both platforms
4. T005 + T006 → Documentation and verification complete

### Single-Developer Sequence

T001 → T002 → T003 → T004 → T005 → T006

### Parallel Execution (Two Developers)

- Developer A: T001 → T003 → T005
- Developer B: T002 → T004 → T006

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- US3 has no dedicated tasks — its acceptance criteria are satisfied by the merge logic in T001/T002
- No test tasks included (no test framework in this project; manual verification via quickstart.md)
- Commit after each task or logical group (T001+T002 together makes sense)
- The plan.md contains exact code snippets for T001, T002, T003, and T004
