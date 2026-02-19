# Research: Install Prompts & Wrapper Middleware

**Branch**: `001-install-prompts-middleware` | **Date**: 2026-02-19

## R1: Interactive Prompting in Piped Node.js Scripts

**Decision**: Use `/dev/tty` to open a direct terminal stream for readline, with try/catch fallback to defaults.

**Rationale**: When the install script runs via `curl -fsSL ... | node`, `process.stdin` is the HTTP pipe, not the terminal. `process.stdin.isTTY` is `undefined`. Opening `/dev/tty` explicitly connects to the controlling terminal regardless of stdin redirection. If `/dev/tty` is unavailable (CI, Docker, Windows), the open fails and the catch block silently uses default values.

**Alternatives considered**:
- `process.stdin.isTTY` check → fails for piped execution (isTTY is undefined, not false)
- `process.stdout.isTTY` check → output TTY doesn't guarantee input availability
- External packages (inquirer, prompts) → not available in `curl | node` context

**Code pattern**:
```javascript
const readline = require('readline');
const fs = require('fs');

async function prompt(question, defaultValue) {
  try {
    const ttyFd = fs.openSync('/dev/tty', 'r+');
    const rl = readline.createInterface({
      input: fs.createReadStream(null, { fd: ttyFd }),
      output: fs.createWriteStream(null, { fd: ttyFd }),
      terminal: true
    });
    const display = `  ${question} [${defaultValue}]: `;
    return new Promise(resolve => {
      rl.question(display, answer => {
        rl.close();
        resolve(answer.trim() || defaultValue);
      });
    });
  } catch {
    return defaultValue; // Non-TTY: use default silently
  }
}
```

## R2: Local Config File Format

**Decision**: Use a bash-sourceable key=value file at `~/.config/claude/local.env`.

**Rationale**: The existing config chain is entirely bash-based (`env.sh` sources `claude-env.sh`). A sourceable local config file fits naturally — the wrapper or remote config can `source` it to override variables. Key=value format with bash quoting is simple, human-editable, and requires no parsing library.

**Alternatives considered**:
- JSON config → requires a parser in bash (jq dependency) or manual parsing
- TOML/YAML → same dependency problem
- Environment variables only → don't persist across sessions
- Separate files per value → unnecessary complexity

**File format**:
```bash
# ~/.config/claude/local.env — User-specific overrides
# Written by install.js, sourced by claude-env.sh
LITELLM_BASE_URL="https://litellm.ai.apro.is"
OP_ITEM="op://Employee/ai.apro.is litellm"
```

## R3: Local Config Override Mechanism

**Decision**: The remote config (`claude-env.sh`) sources the local config file after setting its defaults, allowing local values to override remote defaults.

**Rationale**: This keeps the override mechanism in one place (the remote config) and maintains the existing sourcing chain. The wrapper doesn't need changes for local config — it already sources the remote config, which in turn sources the local overrides. This means the override behavior ships via the remote config update mechanism.

**Alternatives considered**:
- Wrapper sources local config after remote config → requires wrapper changes AND remote config changes
- Installer embeds values into env.sh template → values lost when env.sh is regenerated
- Environment variables in shell profile → outside the wrapper's control, user must manage manually

## R4: Middleware File Location and Behavior

**Decision**: Middleware file at `~/.config/claude/middleware.sh`, sourced by the wrapper script immediately before `exec`.

**Rationale**: Follows XDG convention already used by the project. The `.sh` extension makes the purpose clear. Sourcing (not executing) means the middleware can modify the current shell environment (set variables, alter PATH, etc.) which is the primary use case.

**Alternatives considered**:
- `~/.config/claude/hooks/pre-launch.sh` → subdirectory adds complexity for a single file
- `~/.config/claude/pre-exec.sh` → less descriptive name
- Multiple hook files (pre/post) → YAGNI, spec only calls for pre-exec
- Execute as subprocess → can't modify the wrapper's environment

## R5: Install Script Reads Existing Local Config

**Decision**: The installer reads existing `local.env` (if present) to use as prompt defaults on reinstall.

**Rationale**: FR-005 requires that re-running the installer shows previously stored values as defaults. The installer needs to parse the bash key=value file to extract current values. Since the installer is Node.js, a simple regex extraction is sufficient (no bash sourcing needed).

**Alternatives considered**:
- Store a separate JSON config for the installer → duplication, two sources of truth
- Always use remote defaults on reinstall → violates FR-005
