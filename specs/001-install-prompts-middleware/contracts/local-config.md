# Contract: Local Config File (`local.env`)

**Version**: 1.0 | **Date**: 2026-02-19

## Location

`${XDG_CONFIG_HOME:-$HOME/.config}/claude/local.env`

## Format

Bash-sourceable key=value pairs with double-quoted values.

```bash
# ~/.config/claude/local.env — User-specific overrides
# Written by install.js, sourced by claude-env.sh
LITELLM_BASE_URL="<url>"
OP_ITEM="<1password-reference>"
```

## Contract

### Writer: `install.js`

1. Creates the file with permissions `0600`
2. Writes exactly two key=value pairs: `LITELLM_BASE_URL` and `OP_ITEM`
3. Values are double-quoted to handle special characters
4. File includes a comment header identifying its purpose
5. On reinstall, reads existing file to extract current values as defaults
6. Overwrites the file with new values (preserving or updating)

### Reader: `claude-env.sh` (remote config)

1. Sources the file with `source` (dot-command)
2. Sources AFTER setting default values for `LITELLM_BASE_URL` and `OP_ITEM`
3. Sources BEFORE using those variables for API key retrieval or export
4. Silently skips if the file does not exist (no error, no warning)
5. Does NOT validate the contents — trusts the file as user-controlled

### Parsing by `install.js` (for reinstall defaults)

The installer reads existing `local.env` to extract current values using simple regex:
- Match pattern: `^KEY="VALUE"$` where KEY is `LITELLM_BASE_URL` or `OP_ITEM`
- Ignore comments (lines starting with `#`) and blank lines
- If parsing fails, fall back to remote defaults

## Validation Rules

| Field | Rule | Enforced by |
| ----- | ---- | ----------- |
| `LITELLM_BASE_URL` | Non-empty string | Install script (re-prompts on empty) |
| `OP_ITEM` | Non-empty string starting with `op://` | Install script (re-prompts on invalid) |

## Backward Compatibility

- If the file does not exist, the remote config's hardcoded defaults apply (existing behavior)
- The file is additive — it only overrides the specific variables it defines
- Any additional variables in the file are ignored by the remote config sourcing
