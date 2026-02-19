# Feature Specification: Install Prompts & Wrapper Middleware

**Feature Branch**: `001-install-prompts-middleware`
**Created**: 2026-02-19
**Status**: Draft
**Input**: User description: "As a first-time user of the install script I should be prompted about my litellm base url and 1pass item name for the litellm token. During the automatic update the user shall not be prompted. As a user, I want to have the option to inject custom shell commands right before the actual claude binary is executed in the wrapper script, i.e. the wrapper script should check if a certain middleware file exists and execute it."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - First-Time Interactive Install (Priority: P1)

As a first-time user running the install script, I am prompted for my LiteLLM base URL and 1Password item name so that the wrapper is configured for my environment without editing config files manually.

The installer presents each prompt with the current default value pre-filled. I can press Enter to accept the default or type a custom value. My answers are stored in a local configuration file that persists across remote config updates.

**Why this priority**: Without personalized configuration, the wrapper cannot connect to the correct LiteLLM gateway or retrieve the correct API key. This is the foundational setup step.

**Independent Test**: Run the install script on a machine with no existing configuration. Verify prompts appear, defaults are shown, custom values are persisted, and the wrapper uses them on next invocation.

**Acceptance Scenarios**:

1. **Given** no existing local configuration, **When** I run the install script, **Then** I am prompted for the LiteLLM base URL with the current default shown, and for the 1Password item name with the current default shown.
2. **Given** the install prompts are displayed, **When** I press Enter without typing anything, **Then** the default value is accepted and stored.
3. **Given** the install prompts are displayed, **When** I type a custom value, **Then** my custom value is stored instead of the default.
4. **Given** I have completed the prompts, **When** I run the wrapper script, **Then** the wrapper uses my stored values (custom or default) instead of the remote config's hardcoded values.
5. **Given** a local configuration already exists from a previous install, **When** I run the install script again, **Then** my existing values are shown as the defaults (not the remote config defaults), and I can update or keep them.

---

### User Story 2 - Wrapper Middleware Execution (Priority: P2)

As a user, I want to place a shell script at a well-known location so that its commands are executed right before the claude binary launches. This lets me inject project-specific environment variables, activate virtual environments, run pre-flight checks, or customize the execution environment without modifying the wrapper itself.

**Why this priority**: This enables extensibility and personalization of the wrapper without forking or editing it directly. Important for power users but not required for basic operation.

**Independent Test**: Create a middleware file that exports a test environment variable. Run the wrapper and verify the variable is set when claude starts.

**Acceptance Scenarios**:

1. **Given** the middleware file exists at the expected location, **When** I run the wrapper, **Then** the middleware file is sourced (executed in the current shell context) before the claude binary is launched.
2. **Given** no middleware file exists, **When** I run the wrapper, **Then** the wrapper behaves exactly as it does today — no errors, no warnings.
3. **Given** the middleware file exists and sets environment variables, **When** claude launches, **Then** those environment variables are available to the claude process.
4. **Given** the middleware file contains a syntax error, **When** I run the wrapper, **Then** the error is reported to the user and the wrapper does not proceed to launch claude (fail-safe).

---

### User Story 3 - Silent Automatic Updates (Priority: P1)

As a user whose wrapper automatically refreshes the remote config via the TTL-based cache mechanism, I must not be prompted for any input. The automatic update process retrieves and caches the latest remote config without user interaction.

**Why this priority**: The wrapper runs non-interactively in normal use. Any prompt during TTL refresh would block the shell and break the user experience.

**Independent Test**: Let the remote config cache expire, then run the wrapper. Verify the remote config is refreshed silently and the wrapper launches claude without any prompts.

**Acceptance Scenarios**:

1. **Given** the remote config cache has expired, **When** I invoke the wrapper, **Then** the remote config is fetched and cached silently — no prompts are shown.
2. **Given** the remote config has been updated with new default values, **When** my wrapper auto-updates, **Then** my locally stored personal values are preserved and still take precedence over the remote defaults.

---

### Edge Cases

- What happens when the user provides an empty string (not just pressing Enter) for the LiteLLM URL prompt? The system treats an explicitly empty value as invalid and re-prompts.
- What happens when the install script is run non-interactively (e.g., piped through `curl | node`)? If stdin is not a TTY, the install script uses default values without prompting and informs the user.
- What happens when the middleware file exists but is not executable? The file is sourced (not executed as a subprocess), so the executable bit is not required. This is consistent with how `env.sh` and `claude-env.sh` work.
- What happens when the middleware file takes a long time to execute? The wrapper blocks until the middleware completes. This is the user's responsibility — the wrapper does not impose a timeout.
- What happens when the local config file is deleted after installation? The wrapper falls back to the remote config's default values. The next install run re-prompts.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The install script MUST prompt the user for the LiteLLM base URL during first-time setup, showing the current default value and accepting Enter to keep it.
- **FR-002**: The install script MUST prompt the user for the 1Password item name (full reference path) during first-time setup, showing the current default value and accepting Enter to keep it.
- **FR-003**: The install script MUST store user-provided values in a local configuration file within the config directory that persists independently of the remote config cache.
- **FR-004**: The install script MUST skip all interactive prompts when stdin is not a TTY, using default values instead.
- **FR-005**: The install script MUST use previously stored values as defaults when re-run on a system with existing local configuration.
- **FR-006**: The remote config auto-update mechanism (TTL-based cache refresh) MUST NOT prompt the user for any input under any circumstances.
- **FR-007**: The wrapper script MUST apply locally stored configuration values, giving them precedence over values defined in the remote config.
- **FR-008**: The wrapper script MUST check for the existence of a middleware file at a well-known path within the config directory.
- **FR-009**: The wrapper script MUST source the middleware file (if it exists) after all environment configuration is loaded but immediately before launching the claude binary.
- **FR-010**: The wrapper script MUST NOT produce errors or warnings when the middleware file does not exist.
- **FR-011**: The wrapper script MUST abort with a clear error message if the middleware file exists but contains shell syntax errors (fail-safe via `set -e` propagation).
- **FR-012**: The local configuration file MUST be created with restrictive file permissions (owner-only read/write) to protect potentially sensitive values.

### Key Entities

- **Local Config**: A user-specific configuration file in the config directory that stores personalized values (LiteLLM URL, 1Password item reference). Created by the installer, read by the wrapper. Takes precedence over remote config values.
- **Middleware File**: An optional user-created shell script in the config directory that is sourced by the wrapper before launching claude. Provides a hook for custom pre-execution logic.
- **Remote Config**: The centrally-managed configuration fetched and cached by the wrapper (existing `claude-env.sh`). Provides organization-wide defaults that local config can override.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: First-time users can complete the install with personalized configuration in under 30 seconds (two prompts with defaults).
- **SC-002**: Existing users experience zero disruption — the wrapper launches claude with no additional delay or prompts after the remote config auto-updates.
- **SC-003**: Users can inject custom pre-launch commands via the middleware file without modifying any wrapper or config files managed by the project.
- **SC-004**: 100% of wrapper invocations without a middleware file behave identically to the current behavior (backward compatibility).

## Assumptions

- The install script continues to be run via `curl | node` or directly with `node install.js`. The prompting mechanism must work in both modes (with TTY detection for the piped case).
- The 1Password item reference uses the `op://Vault/Item` format already established in the project.
- The middleware file location follows the same XDG-compatible config directory pattern used by `env.sh` (i.e., `~/.config/claude/`).
- The Windows PowerShell wrapper (`claudestart.ps1`) is out of scope for the middleware feature in this iteration, as the feature description focuses on the shell wrapper.
