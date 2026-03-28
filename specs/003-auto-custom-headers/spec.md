# Feature Specification: Automatic Custom Header Injection

**Feature Branch**: `003-auto-custom-headers`
**Created**: 2026-02-20
**Status**: Draft
**Input**: User description: "Add automatic custom header injection (x-github-repo) into the config scripts, not middleware. Export ANTHROPIC_CUSTOM_HEADERS with metadata derived from the current git repository."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Repo Identification in Requests (Priority: P1)

A developer launches Claude Code from within a git repository. Without any manual configuration, every request to the LiteLLM gateway automatically includes an `x-github-repo` header identifying which repository the developer is working in. This enables the gateway to track usage per repository for billing, auditing, and analytics.

**Why this priority**: This is the core value of the feature — zero-effort metadata tagging of every request with the source repository. It enables per-project usage tracking without developer intervention.

**Independent Test**: Can be fully tested by launching Claude Code in any git repo and inspecting the exported `ANTHROPIC_CUSTOM_HEADERS` environment variable to confirm it contains the repository name.

**Acceptance Scenarios**:

1. **Given** a developer is in a git repository with an `origin` remote, **When** the config scripts run, **Then** `ANTHROPIC_CUSTOM_HEADERS` is exported containing `x-github-repo:<repo-name>`.
2. **Given** a developer is in a directory that is not a git repository, **When** the config scripts run, **Then** `ANTHROPIC_CUSTOM_HEADERS` is either not set or uses a sensible fallback (e.g., the directory name), and the scripts do not error.
3. **Given** a developer has `CLAUDE_PROJECT` explicitly set, **When** the config scripts run, **Then** the header value matches the `CLAUDE_PROJECT` value, consistent with how project detection already works.

---

### User Story 2 - Cross-Platform Parity (Priority: P1)

The custom header injection works identically on both Unix (via `claude-env.sh`) and Windows (via `claudestart.ps1`). A team using mixed operating systems sees the same header behavior regardless of platform.

**Why this priority**: The wrapper already supports both platforms. Shipping this feature on only one platform would break the consistency guarantee and leave a gap in usage tracking.

**Independent Test**: Can be tested by running the bash script on macOS/Linux and the PowerShell script on Windows, then comparing the exported `ANTHROPIC_CUSTOM_HEADERS` value for the same repository.

**Acceptance Scenarios**:

1. **Given** a developer on macOS or Linux sources `claude-env.sh`, **When** running in a git repo, **Then** `ANTHROPIC_CUSTOM_HEADERS` is exported with the correct repo name.
2. **Given** a developer on Windows runs `claudestart.ps1`, **When** running in a git repo, **Then** `ANTHROPIC_CUSTOM_HEADERS` environment variable is set with the same repo name format.

---

### User Story 3 - Header Extensibility (Priority: P2)

A developer or administrator can add additional custom headers alongside the auto-injected `x-github-repo` header. If `ANTHROPIC_CUSTOM_HEADERS` is already set (e.g., via `local.env`, an environment variable, or `middleware.sh`), the auto-injected header is preserved alongside user-defined headers.

**Why this priority**: Some teams may need additional metadata (e.g., team name, cost center). Overwriting user-defined headers would be surprising and limit the feature's usefulness.

**Independent Test**: Can be tested by pre-setting `ANTHROPIC_CUSTOM_HEADERS` to a value, then running the config script and verifying both the original and auto-injected headers are present.

**Acceptance Scenarios**:

1. **Given** `ANTHROPIC_CUSTOM_HEADERS` is not set, **When** the config scripts run, **Then** only `x-github-repo: <repo-name>` is set.
2. **Given** `ANTHROPIC_CUSTOM_HEADERS` is already set to `x-team: platform` (via `local.env` or shell environment), **When** the config scripts run, **Then** the final value contains both `x-team: platform` and `x-github-repo: <repo-name>`.
3. **Given** a developer uses `middleware.sh` to append headers after the config script runs, **When** middleware appends to `ANTHROPIC_CUSTOM_HEADERS`, **Then** both the auto-injected and middleware-added headers are present in the final value.

---

### User Story 4 - Debug Visibility (Priority: P3)

When `CLAUDE_DEBUG=1` is set, the resolved custom headers are printed alongside the existing debug output so developers can verify what headers are being sent.

**Why this priority**: Debugging is a convenience feature. The existing debug output already shows project name, base URL, and model — headers should appear there too.

**Independent Test**: Can be tested by setting `CLAUDE_DEBUG=1`, running the config, and checking stderr for the custom headers output.

**Acceptance Scenarios**:

1. **Given** `CLAUDE_DEBUG=1`, **When** the config scripts run, **Then** the debug output includes the resolved `ANTHROPIC_CUSTOM_HEADERS` value.

---

### Edge Cases

- What happens when `git remote get-url origin` fails (no git, no remote, or not a repo)? The scripts should fall back gracefully, consistent with the existing `detect_project()` behavior.
- What happens when the repo URL contains special characters (e.g., spaces, unicode)? The `sanitize_name()` function already handles this — the header value should use the same sanitized name.
- What happens when the header value separator format changes? The `ANTHROPIC_CUSTOM_HEADERS` format (`Name: Value`) is defined by Claude Code. The scripts should follow whatever format Claude Code expects.
- What happens when multiple headers are needed? Claude Code uses newline separation for multiple headers (e.g., `key1: val1\nkey2: val2`). The merge logic must respect this format.
- What happens when middleware overwrites `ANTHROPIC_CUSTOM_HEADERS` instead of appending? The auto-injected `x-github-repo` header would be lost. Middleware authors must append to (not overwrite) the existing value if they want to preserve the auto-injected header. This is a documentation concern, not a code guard — middleware runs after `claude-env.sh` by design.
- What about middleware on Windows? Middleware (`middleware.sh`) is a Unix-only feature of the `claude` process wrapper. Windows users via `claudestart.ps1` can set additional headers through `local.env` or shell environment variables, but not through middleware.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The configuration scripts MUST automatically export `ANTHROPIC_CUSTOM_HEADERS` containing `x-github-repo:<project-name>` where `<project-name>` is derived from the existing project detection logic.
- **FR-002**: The feature MUST work in both `claude-env.sh` (Bash) and `claudestart.ps1` (PowerShell) with identical output.
- **FR-003**: The feature MUST reuse the existing `detect_project()` / `Get-ClaudeProject` logic for determining the repository name — no duplicate git detection.
- **FR-004**: The scripts MUST preserve any pre-existing `ANTHROPIC_CUSTOM_HEADERS` value by appending the auto-injected header rather than overwriting.
- **FR-005**: The scripts MUST NOT error or prevent Claude Code from launching when project detection fails (e.g., no git repo).
- **FR-006**: When `CLAUDE_DEBUG=1` is set, the resolved custom headers MUST be included in the debug output.

### Key Entities

- **Custom Header**: A key-value pair injected into every Claude API request via the `ANTHROPIC_CUSTOM_HEADERS` environment variable. Format: `Name: Value` (colon + space), multiple headers separated by newlines.
- **Project Name**: The sanitized repository or directory name, already computed by `detect_project()` / `Get-ClaudeProject`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of Claude Code sessions launched from a git repository include the `x-github-repo` header without any manual user configuration.
- **SC-002**: The header injection adds zero additional external commands or network calls beyond what the scripts already execute.
- **SC-003**: Existing user-defined custom headers are preserved in 100% of cases where `ANTHROPIC_CUSTOM_HEADERS` was pre-set.
- **SC-004**: The feature works identically on both supported platforms (Unix Bash and Windows PowerShell).

## Clarifications

### Session 2026-02-20

- Q: Should middleware be documented as a supported header source, and should the spec warn about overwrite risk? → A: Yes — document middleware as a supported integration point for additional headers; add edge case warning that middleware must append (not overwrite) to preserve the auto-injected header.

## Assumptions

- The `ANTHROPIC_CUSTOM_HEADERS` environment variable is the correct mechanism for injecting custom headers into Claude Code requests. The format is `Name: Value` (colon + space) with newline separation for multiple headers, per [Claude Code Settings docs](https://code.claude.com/docs/en/settings).
- The existing `CLAUDE_PROJECT` / `detect_project()` output is a suitable value for the `x-github-repo` header (sanitized, safe for HTTP headers).
- No new dependencies or external tools are needed — this builds entirely on existing script infrastructure.
