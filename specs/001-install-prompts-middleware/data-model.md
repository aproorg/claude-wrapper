# Data Model: Install Prompts & Wrapper Middleware

**Branch**: `001-install-prompts-middleware` | **Date**: 2026-02-19

## Entities

### Local Config File

**Path**: `~/.config/claude/local.env` (XDG_CONFIG_HOME respected)
**Format**: Bash-sourceable key=value pairs
**Permissions**: `0600` (owner read/write only)
**Created by**: Install script (`install.js`)
**Read by**: Remote config (`claude-env.sh`) via `source`

| Field | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `LITELLM_BASE_URL` | URL string | Yes | `https://litellm.ai.apro.is` | LiteLLM gateway endpoint |
| `OP_ITEM` | 1Password reference | Yes | `op://Employee/ai.apro.is litellm` | 1Password item path for API key lookup |

**Validation rules**:
- `LITELLM_BASE_URL` must be a non-empty string (URL format validation is optional — the user may use internal hostnames)
- `OP_ITEM` must be a non-empty string starting with `op://`

**State transitions**: None — the file is static configuration, not stateful.

### Middleware File

**Path**: `~/.config/claude/middleware.sh` (XDG_CONFIG_HOME respected)
**Format**: Bash script (sourced, not executed)
**Permissions**: No specific requirement (sourced, not executed — executable bit irrelevant)
**Created by**: User (manually)
**Read by**: Wrapper script (`claude`) via `source`

This entity has no schema — it is an opaque shell script. The contract is behavioral:
- It is sourced in the wrapper's shell context
- It can read/modify environment variables
- It can access all variables set by the remote config
- Shell errors propagate to the wrapper (fail-safe via `set -e`)

### Remote Config (existing, modified)

**Path**: Fetched from GitHub, cached at `~/.cache/claude/env-remote.sh`
**Modification**: Add sourcing of local config file after setting defaults

The remote config sets default values for `LITELLM_BASE_URL` and `OP_ITEM`, then sources the local config (if it exists) to allow overrides before using those values for API key retrieval and environment export.

## Relationships

```
install.js ──creates──> local.env
                            │
claude (wrapper) ──sources──> env.sh ──sources──> claude-env.sh (remote, cached)
                                                       │
                                                  sources local.env (overrides)
                                                       │
claude (wrapper) ──sources──> middleware.sh (if exists)
                     │
                     └──exec──> claude binary
```

## File Lifecycle

| Event | local.env | middleware.sh | env-remote.sh |
| ----- | --------- | ------------- | ------------- |
| First install | Created with prompted/default values | Not created | Fetched and cached |
| Reinstall | Read for defaults, updated with new values | Untouched | Re-fetched |
| Wrapper invocation | Sourced by remote config | Sourced by wrapper | Sourced by env.sh |
| Auto-update (TTL) | Untouched | Untouched | Re-fetched silently |
| `--clear-cache` | Untouched | Untouched | Deleted |
| Manual deletion | Wrapper uses remote defaults | Wrapper skips sourcing | Re-fetched on next run |
