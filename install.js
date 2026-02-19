#!/usr/bin/env node
// Claude Code Environment Installer
// Usage: curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node
//
// Installs a process wrapper at ~/.local/bin/claude that:
//   - Shadows the real Claude Code binary
//   - Fetches and caches team configuration from a central URL
//   - Retrieves API keys from 1Password
//   - Forwards all arguments to the real Claude Code binary
//
// Options (via environment variables):
//   CLAUDE_ENV_URL    Override the remote env script URL
//   CLAUDE_FORCE=1    Overwrite existing wrapper without prompting

"use strict";

const fs = require("fs");
const path = require("path");
const os = require("os");
const https = require("https");
const { execSync } = require("child_process");

// ============================================================================
// Configuration
// ============================================================================
const REMOTE_ENV_URL =
  process.env.CLAUDE_ENV_URL ||
  "https://raw.githubusercontent.com/aproorg/claude-wrapper/main/claude-env.sh";

// ============================================================================
// Output helpers
// ============================================================================
const color = (code, text) =>
  process.stderr.isTTY ? `\x1b[${code}m${text}\x1b[0m` : text;

const info = (msg) => console.error(`  ${color(34, "[INFO]")}  ${msg}`);
const ok = (msg) => console.error(`  ${color(32, "[OK]")}    ${msg}`);
const warn = (msg) => console.error(`  ${color(33, "[WARN]")}  ${msg}`);
const error = (msg) => console.error(`  ${color(31, "[ERROR]")} ${msg}`);

function die(msg) {
  error(msg);
  process.exit(1);
}

// ============================================================================
// Platform detection
// ============================================================================
function detectPlatform() {
  switch (process.platform) {
    case "darwin":
      return "macos";
    case "linux":
      try {
        const version = fs.readFileSync("/proc/version", "utf8");
        if (/microsoft/i.test(version)) return "wsl";
      } catch {}
      return "linux";
    case "win32":
      return "windows";
    default:
      return "unknown";
  }
}

// ============================================================================
// Helpers
// ============================================================================
function commandExists(cmd) {
  try {
    const check =
      process.platform === "win32" ? `where ${cmd}` : `command -v ${cmd}`;
    execSync(check, { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

function fetch(url) {
  return new Promise((resolve, reject) => {
    const get = url.startsWith("https") ? https.get : require("http").get;
    get(url, { timeout: 10_000 }, (res) => {
      if (
        res.statusCode >= 300 &&
        res.statusCode < 400 &&
        res.headers.location
      ) {
        return fetch(res.headers.location).then(resolve, reject);
      }
      if (res.statusCode !== 200) {
        return reject(new Error(`HTTP ${res.statusCode}`));
      }
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
      res.on("error", reject);
    }).on("error", reject);
  });
}

// ============================================================================
// Paths
// ============================================================================
function installBinDir() {
  return path.join(os.homedir(), ".local", "bin");
}

function configDir() {
  return path.join(
    process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config"),
    "claude",
  );
}

function cacheDir() {
  return path.join(
    process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache"),
    "claude",
  );
}

// ============================================================================
// Shell profile detection
// ============================================================================
function detectShellProfile() {
  const shell = process.env.SHELL || "";
  const home = os.homedir();

  if (shell.endsWith("/zsh")) {
    return path.join(home, ".zshrc");
  }
  if (shell.endsWith("/bash")) {
    const bashrc = path.join(home, ".bashrc");
    if (fs.existsSync(bashrc)) return bashrc;
    return path.join(home, ".bash_profile");
  }
  return path.join(home, ".profile");
}

function ensureOnPath(binDir) {
  // Already on PATH
  const dirs = (process.env.PATH || "").split(":");
  if (dirs.includes(binDir)) return null;

  const profile = detectShellProfile();

  // Profile already references the dir
  try {
    const content = fs.readFileSync(profile, "utf8");
    if (content.includes(binDir)) return null;
  } catch {}

  const line = '\nexport PATH="' + binDir + ':$PATH"\n';
  fs.appendFileSync(profile, line);
  return profile;
}

// ============================================================================
// Process wrapper script
// ============================================================================
function wrapperScript(remoteUrl) {
  return [
    "#!/usr/bin/env bash",
    "# claude — Process wrapper for Claude Code",
    "# Fetches remote config, sets up environment, and launches the real binary.",
    "#",
    "# Installed by: curl -fsSL .../install.js | node",
    "# Update:       rm ~/.cache/claude/env-remote.sh",
    "# Debug:        CLAUDE_DEBUG=1 claude",
    "",
    "set -euo pipefail",
    "",
    "# ── Real binary ──────────────────────────────────────────────────────────────",
    "# Find the actual claude binary, skipping this wrapper",
    'CLAUDE_BIN=""',
    "while IFS= read -r candidate; do",
    '  [[ "$(readlink -f "$candidate" 2>/dev/null || echo "$candidate")" == "$(readlink -f "$0" 2>/dev/null || echo "$0")" ]] && continue',
    '  CLAUDE_BIN="$candidate"',
    "  break",
    "done < <(which -a claude 2>/dev/null)",
    "",
    'if [[ -z "$CLAUDE_BIN" ]]; then',
    '  echo "ERROR: Cannot find the real claude binary" >&2',
    "  exit 1",
    "fi",
    "",
    "# ── Remote config fetch + cache ──────────────────────────────────────────────",
    'CLAUDE_ENV_REMOTE_URL="${CLAUDE_ENV_URL:-' + remoteUrl + '}"',
    '_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude"',
    '_CACHE_FILE="$_CACHE_DIR/env-remote.sh"',
    '_UPDATE_TTL="${CLAUDE_ENV_UPDATE_TTL:-300}"',
    "",
    "_needs_update() {",
    '  [[ ! -f "$_CACHE_FILE" ]] && return 0',
    "  local age",
    '  age=$(($(date +%s) - $(stat -f %m "$_CACHE_FILE" 2>/dev/null || stat -c %Y "$_CACHE_FILE" 2>/dev/null || echo 0)))',
    "  [[ $age -ge $_UPDATE_TTL ]]",
    "}",
    "",
    "if _needs_update; then",
    '  (umask 077; mkdir -p "$_CACHE_DIR")',
    '  tmp="$_CACHE_FILE.tmp.$$"',
    '  if (umask 077; curl -fsSL --connect-timeout 3 --max-time 10 "$CLAUDE_ENV_REMOTE_URL" -o "$tmp") 2>/dev/null; then',
    '    mv "$tmp" "$_CACHE_FILE"',
    "  else",
    '    rm -f "$tmp"',
    '    if [[ ! -f "$_CACHE_FILE" ]]; then',
    '      echo "ERROR: Cannot fetch config from $CLAUDE_ENV_REMOTE_URL (no cache)" >&2',
    "      exit 1",
    "    fi",
    "  fi",
    "fi",
    "",
    "# ── Source remote config (sets ANTHROPIC_* exports) ──────────────────────────",
    "# shellcheck disable=SC1090",
    'source "$_CACHE_FILE"',
    "",
    "# ── Middleware ────────────────────────────────────────────────────────────────",
    '_CLAUDE_MIDDLEWARE="${XDG_CONFIG_HOME:-$HOME/.config}/claude/middleware.sh"',
    'if [[ -f "$_CLAUDE_MIDDLEWARE" ]]; then',
    "  # shellcheck disable=SC1090",
    '  source "$_CLAUDE_MIDDLEWARE"',
    "fi",
    "unset _CLAUDE_MIDDLEWARE",
    "",
    "# ── Launch ───────────────────────────────────────────────────────────────────",
    'exec "$CLAUDE_BIN" "$@"',
    "",
  ].join("\n");
}

// ============================================================================
// Interactive prompting (via /dev/tty for curl-pipe compatibility)
// ============================================================================
function prompt(question, defaultValue) {
  return new Promise((resolve) => {
    try {
      const tty = fs.openSync("/dev/tty", "r+");
      const rl = require("readline").createInterface({
        input: new fs.createReadStream(null, { fd: tty }),
        output: new fs.createWriteStream(null, { fd: tty }),
      });
      const display = defaultValue
        ? `${question} [${defaultValue}]: `
        : `${question}: `;
      rl.question(display, (answer) => {
        rl.close();
        resolve(answer.trim() || defaultValue || "");
      });
    } catch {
      resolve(defaultValue || "");
    }
  });
}

// ============================================================================
// Local config (local.env) read/write
// ============================================================================
function readLocalConfig(filePath) {
  const values = {};
  try {
    const content = fs.readFileSync(filePath, "utf8");
    for (const line of content.split("\n")) {
      const m = line.match(/^(LITELLM_BASE_URL|OP_ITEM)="(.*)"\s*$/);
      if (m) values[m[1]] = m[2];
    }
  } catch {}
  return values;
}

function writeLocalConfig(filePath, values) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const content = [
    "# ~/.config/claude/local.env — User-specific overrides",
    "# Written by install.js, sourced by claude-env.sh",
    `LITELLM_BASE_URL="${values.LITELLM_BASE_URL}"`,
    `OP_ITEM="${values.OP_ITEM}"`,
    "",
  ].join("\n");
  fs.writeFileSync(filePath, content, { mode: 0o600 });
}

// ============================================================================
// Installation
// ============================================================================
async function install(platform) {
  const binDir = installBinDir();
  const cfgDir = configDir();
  const cchDir = cacheDir();
  const wrapperPath = path.join(binDir, "claude");

  info(`Platform: ${platform}`);
  info(`Wrapper:  ${wrapperPath}`);

  // Create directories
  fs.mkdirSync(binDir, { recursive: true, mode: 0o755 });
  fs.mkdirSync(cfgDir, { recursive: true, mode: 0o755 });
  fs.mkdirSync(cchDir, { recursive: true, mode: 0o700 });
  try {
    fs.chmodSync(cchDir, 0o700);
  } catch {}

  // Clean up old env.sh bootstrap from previous install method (no longer used)
  const oldEnvSh = path.join(cfgDir, "env.sh");
  if (fs.existsSync(oldEnvSh)) {
    fs.unlinkSync(oldEnvSh);
    info("Removed old env.sh bootstrap (no longer needed)");
  }

  // Handle existing wrapper
  if (fs.existsSync(wrapperPath) && process.env.CLAUDE_FORCE !== "1") {
    const stat = fs.lstatSync(wrapperPath);
    if (stat.isSymbolicLink()) {
      const target = fs.readlinkSync(wrapperPath);
      info(`Replacing symlink ${wrapperPath} → ${target}`);
      fs.unlinkSync(wrapperPath);
    } else {
      const backup = `${wrapperPath}.backup.${Date.now()}`;
      fs.copyFileSync(wrapperPath, backup);
      info(`Backed up existing wrapper to ${backup}`);
    }
  }

  // Write the process wrapper
  fs.writeFileSync(wrapperPath, wrapperScript(REMOTE_ENV_URL), {
    mode: 0o755,
  });
  ok(`Wrote ${wrapperPath}`);

  // Ensure ~/.local/bin is on PATH
  const modifiedProfile = ensureOnPath(binDir);
  if (modifiedProfile) {
    ok(`Added ${binDir} to PATH in ${modifiedProfile}`);
    warn("Restart your shell or run: source " + modifiedProfile);
  } else {
    ok(`${binDir} is already on PATH`);
  }

  // Pre-fetch the remote config
  info("Fetching remote configuration...");
  try {
    const remoteEnv = await fetch(REMOTE_ENV_URL);
    const cachePath = path.join(cchDir, "env-remote.sh");
    fs.writeFileSync(cachePath, remoteEnv, { mode: 0o600 });
    ok("Remote configuration cached");
  } catch (err) {
    warn(`Could not fetch remote configuration: ${err.message}`);
    warn(`  URL: ${REMOTE_ENV_URL}`);
    warn("The wrapper will retry on next Claude invocation");
  }

  // Interactive prompts for local config
  const localEnvPath = path.join(cfgDir, "local.env");
  const existing = readLocalConfig(localEnvPath);
  const defaultUrl =
    existing.LITELLM_BASE_URL || "https://litellm.ai.apro.is";
  const defaultItem = existing.OP_ITEM || "op://Employee/ai.apro.is litellm";

  console.error("");
  info("Configure your local connection settings:");
  console.error("");

  let litellmUrl = "";
  while (!litellmUrl) {
    litellmUrl = await prompt("  LiteLLM base URL", defaultUrl);
  }

  let opItem = "";
  while (!opItem || !opItem.startsWith("op://")) {
    opItem = await prompt("  1Password item (op://...)", defaultItem);
    if (opItem && !opItem.startsWith("op://")) {
      warn("Must start with op:// — try again");
      opItem = "";
    }
  }

  writeLocalConfig(localEnvPath, {
    LITELLM_BASE_URL: litellmUrl,
    OP_ITEM: opItem,
  });
  ok(`Wrote ${localEnvPath}`);
}

// ============================================================================
// Prerequisites
// ============================================================================
function checkPrerequisites() {
  if (!commandExists("claude")) {
    die(
      "Claude Code must be installed first (brew install claude-code, or npm install -g @anthropic-ai/claude-code)",
    );
  }

  if (!commandExists("curl")) {
    die("curl is required (used by the wrapper for fetching config updates)");
  }

  if (!commandExists("op")) {
    warn("1Password CLI (op) not found — API key management will not work");
    warn("Install: https://developer.1password.com/docs/cli/get-started/");
  }

  if (!commandExists("git")) {
    warn("git not found — project detection will fall back to directory name");
  }
}

// ============================================================================
// Main
// ============================================================================
async function main() {
  console.error("");
  console.error("  Claude Code Environment Installer");
  console.error("  " + "─".repeat(35));
  console.error("");

  const platform = detectPlatform();
  if (platform === "windows") {
    die(
      "Windows is not supported by this installer. Use claudestart.ps1 instead.",
    );
  }
  if (platform === "unknown") {
    die(`Unsupported platform: ${process.platform}`);
  }

  checkPrerequisites();
  await install(platform);

  ok("Installation complete!");
  console.error("");
  console.error(
    "  The wrapper at ~/.local/bin/claude shadows the real binary,",
  );
  console.error("  injects your team config, and forwards all arguments.");
  console.error("");
  console.error("  Commands:");
  console.error("    Verify:         which claude  (should show ~/.local/bin/claude)");
  console.error("    Debug:          CLAUDE_DEBUG=1 claude");
  console.error("    Force refresh:  rm ~/.cache/claude/env-remote.sh");
  console.error("");
}

main().catch((err) => die(err.message));
