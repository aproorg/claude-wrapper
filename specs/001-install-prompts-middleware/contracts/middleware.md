# Contract: Middleware File (`middleware.sh`)

**Version**: 1.0 | **Date**: 2026-02-19

## Location

`${XDG_CONFIG_HOME:-$HOME/.config}/claude/middleware.sh`

## Format

Any valid bash script. No specific structure required.

## Contract

### Caller: `claude` (wrapper script)

1. Checks if the file exists at the well-known path
2. If it exists, sources it with `source` (dot-command) in the current shell context
3. Sources AFTER all environment configuration is loaded (remote config + local overrides)
4. Sources IMMEDIATELY BEFORE `exec "$CLAUDE_BIN" "$@"`
5. If the file does not exist, skips silently (no error, no warning, no log)
6. Shell errors in the middleware file propagate via `set -e` — the wrapper aborts

### Implementer: User (manually created)

The middleware file can:
- Read all environment variables set by the config chain
- Modify environment variables (e.g., override `ANTHROPIC_MODEL`)
- Export new environment variables
- Run arbitrary commands (e.g., activate a virtualenv, log invocations)
- Access `$@` (the arguments being passed to claude) — though this is not guaranteed across shell implementations

The middleware file must NOT:
- Prompt for user input (the wrapper may run non-interactively)
- Call `exec` (would replace the wrapper process before claude launches)
- Call `exit` (would terminate the wrapper)

## Execution Context

| Property | Value |
| -------- | ----- |
| Shell | bash (inherits from wrapper's `#!/usr/bin/env bash`) |
| Working directory | User's current directory (where they ran `claude`) |
| `set -e` | Active (errors abort) |
| `set -u` | Active (unset variables are errors) |
| `set -o pipefail` | Active |
| Available variables | All `ANTHROPIC_*`, `CLAUDE_*`, `LITELLM_BASE_URL`, `OP_ITEM`, etc. |

## Error Handling

- **Syntax error**: Wrapper aborts with bash's error message (e.g., `middleware.sh: line 5: syntax error`)
- **Command failure**: Wrapper aborts due to `set -e` (e.g., a failed `curl` in middleware)
- **Missing file**: No-op, no output

## Examples

### Add a custom environment variable
```bash
export MY_CUSTOM_FLAG="enabled"
```

### Log every claude invocation
```bash
echo "$(date -Iseconds) claude $*" >> ~/.local/share/claude/invocations.log
```

### Override model for a specific directory
```bash
if [[ "$PWD" == */my-experimental-project* ]]; then
  export ANTHROPIC_MODEL="claude-sonnet-4-6"
fi
```
