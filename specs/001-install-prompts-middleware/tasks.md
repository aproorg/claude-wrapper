# Tasks: Install Prompts & Wrapper Middleware

**Input**: Design documents from `/specs/001-install-prompts-middleware/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/, research.md, quickstart.md

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story. US1 and US3 share a foundational dependency (local config sourcing in `claude-env.sh`). US2 is independently implementable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No setup tasks needed — all modifications are to existing files at the repository root. No new directories, dependencies, or project structure changes.

*(Phase intentionally empty — proceed to Phase 2)*

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add local config sourcing to the remote config so user-specific values can override defaults. This is the shared infrastructure for US1 (install prompts write the config) and US3 (auto-updates preserve it).

- [x] T001 Add local.env sourcing block after default values in `claude-env.sh`

**Details for T001**: Insert a block after line 11 (after `OP_ITEM=...`, before the Models section) that computes `_CLAUDE_LOCAL_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/claude/local.env"`, checks if the file exists, sources it, and unsets the path variable. See `plan.md` Change 1 and `contracts/local-config.md` Reader contract. Use `# shellcheck disable=SC1090` above the `source` line.

**Checkpoint**: After T001, manually creating `~/.config/claude/local.env` with `LITELLM_BASE_URL="http://test"` should override the hardcoded default when the wrapper runs.

---

## Phase 3: User Story 1 — First-Time Interactive Install (Priority: P1)

**Goal**: The install script prompts for LiteLLM URL and 1Password item name, stores values in `local.env`, and shows existing values as defaults on reinstall.

**Independent Test**: Run `node install.js` on a clean system. Verify prompts appear with defaults, custom values are stored in `~/.config/claude/local.env`, and the wrapper uses them.

### Implementation for User Story 1

- [x] T002 [US1] Add `prompt(question, defaultValue)` helper function using `/dev/tty` + readline in `install.js`

**Details for T002**: Open `/dev/tty` as both input and output for the readline interface (see `research.md` R1). Wrap in try/catch — if `/dev/tty` is unavailable (CI, Docker, piped mode), return the default value silently. Close the readline interface after each call. This satisfies FR-004 (skip prompts when not interactive).

- [x] T003 [US1] Add `readLocalConfig(filePath)` function to parse existing `local.env` values in `install.js`

**Details for T003**: Read the file with `fs.readFileSync`, match lines against `/^(LITELLM_BASE_URL|OP_ITEM)="(.*)"\s*$/` regex, return an object with found values. If the file doesn't exist or parsing fails, return empty object. See `contracts/local-config.md` Parsing section and `research.md` R5.

- [x] T004 [US1] Add `writeLocalConfig(filePath, values)` function with `0600` permissions in `install.js`

**Details for T004**: Ensure parent directory exists (`fs.mkdirSync` with `recursive: true`). Write file content with comment header, `LITELLM_BASE_URL="..."` and `OP_ITEM="..."` lines. Set permissions to `0o600`. See `contracts/local-config.md` Writer contract and FR-012.

- [x] T005 [US1] Add interactive prompt flow with validation in the `install()` function in `install.js`

**Details for T005**: After the existing `env.sh` write block (around line 200), add the prompt sequence:
1. Compute local config path: `path.join(configDir, 'local.env')`
2. Call `readLocalConfig()` to get existing values (for reinstall defaults per FR-005)
3. Determine defaults: existing values take priority, then fall back to remote defaults (`https://litellm.ai.apro.is` and `op://Employee/ai.apro.is litellm`)
4. Call `prompt()` for LiteLLM URL — re-prompt if empty (FR-001)
5. Call `prompt()` for 1Password item — re-prompt if empty or doesn't start with `op://` (FR-002, validation from `contracts/local-config.md`)
6. Call `writeLocalConfig()` with the collected values (FR-003)

**Checkpoint**: At this point, running `node install.js` should prompt for two values, store them in `~/.config/claude/local.env` with `0600` permissions, and re-running should show previous values as defaults.

---

## Phase 4: User Story 3 — Silent Automatic Updates (Priority: P1)

**Goal**: The wrapper's TTL-based cache refresh fetches remote config silently. User's local values persist and override updated remote defaults.

**Independent Test**: Let the cache expire (wait 5 min or delete `~/.cache/claude/env-remote.sh`), run the wrapper, verify no prompts appear and local.env values are still used.

### Implementation for User Story 3

No implementation tasks required. This story is satisfied by the architecture:

1. **No prompts in wrapper path**: Prompting code lives exclusively in `install.js`. The wrapper (`claude`) and remote config (`claude-env.sh`) never prompt. The TTL refresh in the wrapper only runs `curl` to re-fetch the remote config — no interactive code. (FR-006)
2. **Local values persist**: Phase 2 (T001) ensures `local.env` is sourced after remote defaults. Since `local.env` lives in `~/.config/claude/` (not the cache directory), it is untouched by cache refresh or `--clear-cache`. (FR-007)

**Checkpoint**: Verify by inspecting the wrapper's cache refresh path (lines 30-50 in `claude`) — confirm it only runs `curl` and `source`, with no `read` or prompt calls.

---

## Phase 5: User Story 2 — Wrapper Middleware Execution (Priority: P2)

**Goal**: The wrapper sources `~/.config/claude/middleware.sh` (if it exists) right before launching the claude binary, allowing users to inject custom shell commands.

**Independent Test**: Create `~/.config/claude/middleware.sh` with `export MY_TEST_VAR="hello"`, run the wrapper, verify the variable is set. Delete the file, run again, verify no errors.

### Implementation for User Story 2

- [x] T006 [US2] Add middleware sourcing block before `exec` in the `claude` wrapper script

**Details for T006**: Insert a block after line 54 (`source "$_CACHE_FILE"`) and before line 57 (`exec "$CLAUDE_BIN" "$@"`). Compute `_CLAUDE_MIDDLEWARE="${XDG_CONFIG_HOME:-$HOME/.config}/claude/middleware.sh"`, check if the file exists, source it with `# shellcheck disable=SC1090`, then unset the path variable. See `plan.md` Change 3 and `contracts/middleware.md`. Do NOT add error handling — `set -e` already propagates errors (FR-011). Do NOT add logging for missing file (FR-010).

**Checkpoint**: `echo 'export MY_TEST_VAR="hello"' > ~/.config/claude/middleware.sh && claude -p 'echo $MY_TEST_VAR'` should show "hello". Removing the file should produce no errors.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validate the full feature end-to-end using quickstart scenarios.

- [x] T007 Run all quickstart.md validation scenarios end-to-end

**Details for T007**: Execute each test scenario from `quickstart.md`:
1. First-time install (interactive): `node install.js` — verify prompts, defaults, custom values stored
2. Piped install (non-interactive): Verify defaults used silently when `/dev/tty` unavailable
3. Reinstall: `node install.js` again — verify previous values shown as defaults
4. Local config verification: `cat ~/.config/claude/local.env` — verify format matches contract
5. Wrapper override verification: Run wrapper, confirm local values used over remote defaults
6. Middleware test: Create test middleware, verify sourcing; remove, verify no errors
7. Syntax error test: Create middleware with syntax error, verify wrapper aborts with error message

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Empty — proceed immediately
- **Foundational (Phase 2)**: No dependencies — T001 can start immediately
- **US1 (Phase 3)**: Depends on T001 (needs local.env sourcing to verify end-to-end)
- **US3 (Phase 4)**: Depends on T001 (local.env sourcing is the mechanism that satisfies US3)
- **US2 (Phase 5)**: No dependency on T001 — can run in parallel with Phase 3
- **Polish (Phase 6)**: Depends on all implementation phases (T001–T006)

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational (Phase 2). No dependencies on other stories.
- **US3 (P1)**: Depends on Foundational (Phase 2). No implementation tasks — verification only.
- **US2 (P2)**: Independent of all other stories. Can start after Phase 1 (immediately).

### Within User Story 1

- T002, T003, T004 are helper functions — they don't depend on each other but all modify `install.js` (same file, execute sequentially)
- T005 depends on T002, T003, T004 (calls all three helpers)

### Parallel Opportunities

- **T001 and T006** can run in parallel (different files: `claude-env.sh` vs `claude`)
- **T002–T005** must be sequential (all modify `install.js`)
- **US2 (Phase 5)** can run in parallel with US1 (Phase 3) — different files entirely

---

## Parallel Example: Fastest Path

```text
# Start both foundational and US2 in parallel (different files):
Parallel Group A:
  T001: Add local.env sourcing in claude-env.sh
  T006: Add middleware sourcing in claude wrapper

# After T001 completes, start US1 sequentially (same file):
Sequential:
  T002: Add prompt() function in install.js
  T003: Add readLocalConfig() in install.js
  T004: Add writeLocalConfig() in install.js
  T005: Add prompt flow in install.js

# After all tasks complete:
  T007: Run quickstart.md validation scenarios
```

---

## Implementation Strategy

### MVP First (US1 + US3)

1. Complete T001 (Foundational) — local config sourcing
2. Complete T002–T005 (US1) — install prompts
3. **STOP and VALIDATE**: Test US1 independently (install, reinstall, piped mode)
4. US3 is inherently satisfied — verify at checkpoint

### Full Feature

5. Complete T006 (US2) — middleware hook
6. Complete T007 (Polish) — end-to-end validation
7. Feature complete

### Parallel Strategy

With two developers:
- Developer A: T001 → T002 → T003 → T004 → T005 (foundational + US1)
- Developer B: T006 (US2, independent)
- Together: T007 (end-to-end validation)

---

## Notes

- Total tasks: 7 (5 implementation + 1 verification-only phase + 1 validation)
- All implementation touches exactly 3 existing files — no new files created
- No test framework — validation is manual per quickstart.md scenarios
- US3 requires no code — it's satisfied by the architecture (prompts in installer, not wrapper)
- The [P] marker is not used on individual tasks because US1 tasks share a file (`install.js`), but entire phases (US1 vs US2) can run in parallel
