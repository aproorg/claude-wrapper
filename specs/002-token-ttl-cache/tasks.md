# Tasks: Reliable LiteLLM Token TTL Cache

**Input**: Design documents from `/specs/002-token-ttl-cache/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: Not requested in the feature specification. No test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: No project initialization needed — all target files already exist. This phase is empty.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No shared infrastructure to add. The cache directory, file layout, and `--clear-cache` mechanism already exist and work correctly. This phase is empty.

**Checkpoint**: Foundation ready — user story implementation can begin.

---

## Phase 3: User Story 1 - Cached API Key Skips 1Password (Priority: P1) MVP

**Goal**: After the first invocation fetches from 1Password, subsequent invocations within 12 hours use the cached key without triggering any 1Password prompt.

**Independent Test**: Run `CLAUDE_DEBUG=1 claude --version` twice. First run shows `key=fetched`; second run shows `key=cached` and does not prompt 1Password.

### Implementation for User Story 1

- [x] T001 [P] [US1] Add empty-file guard to `get_api_key` cache read in claude-env.sh — check `[ -s "$cache_file" ]` before using cached key; treat empty files as cache miss
- [x] T002 [P] [US1] Add atomic write to `get_api_key` cache write in claude-env.sh — write to `"$cache_file.tmp.$$"` then `mv` to `"$cache_file"` (replace the direct `echo "$key" >"$cache_file"`)
- [x] T003 [US1] Add debug cache-hit logging to `get_api_key` in claude-env.sh — when `CLAUDE_DEBUG=1`, print `key=cached` on cache hit or `key=fetched` on 1Password fetch (to stderr)

**Checkpoint**: US1 complete — `claude-env.sh` cache is hardened. macOS and Linux users get reliable caching with visible debug output.

---

## Phase 4: User Story 2 - Cache Works on macOS, Linux, and Windows (Priority: P1)

**Goal**: The same caching fixes applied in US1 (bash) are applied to the PowerShell wrapper so Windows users get identical behavior.

**Independent Test**: On Windows, run `$env:CLAUDE_DEBUG = "1"; claudestart --version` twice. First run shows `key=fetched`; second run shows `key=cached`.

### Implementation for User Story 2

- [x] T004 [P] [US2] Add empty-file guard to `Get-ApiKey` cache read in claudestart.ps1 — check file size > 0 before using cached key; treat empty files as cache miss
- [x] T005 [P] [US2] Add atomic write to `Get-ApiKey` cache write in claudestart.ps1 — write to temp file then `Move-Item` to final path (replace direct `Out-File`)
- [x] T006 [US2] Add debug cache-hit logging to `Get-ApiKey` in claudestart.ps1 — when `$env:CLAUDE_DEBUG -eq "1"`, print `key=cached` or `key=fetched` to host

**Checkpoint**: US2 complete — Windows users get the same hardened caching. Both platforms are now consistent.

---

## Phase 5: User Story 3 - Cache Clear and Manual Refresh (Priority: P2)

**Goal**: The `--clear-cache` command works reliably and the wrapper recovers by fetching a fresh key.

**Independent Test**: Run `claude --clear-cache`, confirm `.key` files are gone, then run `CLAUDE_DEBUG=1 claude --version` and confirm `key=fetched`.

### Implementation for User Story 3

- [x] T007 [US3] Verify `--clear-cache` in claude-env.sh handles the case where cache directory or `.key` files don't exist (no-op, no error)
- [x] T008 [US3] Verify `--clear-cache` in claudestart.ps1 handles the case where cache directory or `.key` files don't exist (no-op, no error)

**Checkpoint**: US3 complete — cache clear and recovery path is verified on both platforms.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Verification and documentation updates.

- [x] T009 Run quickstart.md E2E validation on macOS (all 3 verification scenarios)
- [x] T010 [P] Update README.md E2E Testing section to include the new `key=cached` / `key=fetched` debug output in expected results

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Empty — nothing to do
- **Foundational (Phase 2)**: Empty — nothing to do
- **US1 (Phase 3)**: Can start immediately — modifies `claude-env.sh` only
- **US2 (Phase 4)**: Can start immediately in parallel with US1 — modifies `claudestart.ps1` only
- **US3 (Phase 5)**: Can start after US1 and US2 (verifies behavior of the code they changed)
- **Polish (Phase 6)**: Depends on US1, US2, US3 completion

### User Story Dependencies

- **User Story 1 (P1)**: No dependencies — targets `claude-env.sh` only
- **User Story 2 (P1)**: No dependencies — targets `claudestart.ps1` only. Can run in parallel with US1.
- **User Story 3 (P2)**: Depends on US1 and US2 (verifies their changes work with `--clear-cache`)

### Within Each User Story

- Empty-file guard (read path) and atomic write (write path) are independent — marked [P]
- Debug logging depends on the guard being in place to log the correct path

### Parallel Opportunities

- T001 and T002 can run in parallel (different code paths in same file, but non-overlapping functions)
- T004 and T005 can run in parallel (same reasoning for PowerShell)
- US1 (T001-T003) and US2 (T004-T006) can run entirely in parallel (different files)
- T009 and T010 can run in parallel

---

## Parallel Example: User Stories 1 & 2

```text
# US1 and US2 target different files — full parallel execution:
Agent A: T001 [US1] Empty-file guard in claude-env.sh
Agent B: T004 [US2] Empty-file guard in claudestart.ps1

Agent A: T002 [US1] Atomic write in claude-env.sh
Agent B: T005 [US2] Atomic write in claudestart.ps1

Agent A: T003 [US1] Debug logging in claude-env.sh
Agent B: T006 [US2] Debug logging in claudestart.ps1
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001, T002, T003 in `claude-env.sh`
2. **STOP and VALIDATE**: Run quickstart.md scenarios on macOS/Linux
3. Deploy if ready — macOS/Linux users get the fix immediately

### Incremental Delivery

1. US1 (bash) → Validate → Ship to macOS/Linux users
2. US2 (PowerShell) → Validate → Ship to Windows users
3. US3 (clear-cache verification) → Confirm both platforms recover correctly
4. Polish → Update docs with new debug output

### Parallel Team Strategy

With two developers:
1. Developer A: US1 (`claude-env.sh`)
2. Developer B: US2 (`claudestart.ps1`)
3. Both complete → either developer handles US3 + Polish

---

## Notes

- [P] tasks = different code paths or different files, no dependencies
- [Story] label maps task to specific user story for traceability
- US1 and US2 are both P1 but target different files — true parallel
- Total changes: ~15 lines in `claude-env.sh`, ~10 lines in `claudestart.ps1`
- No new files, no new dependencies, no config changes
