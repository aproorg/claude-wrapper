#!/usr/bin/env node
// Claude Code Environment Installer
// Usage: curl -fsSL https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.js | node
//
// Options (via environment variables):
//   CLAUDE_ENV_URL    Override the remote env script URL
//   CLAUDE_FORCE=1    Overwrite existing env.sh without prompting

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
      // Detect WSL
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
    const check = process.platform === "win32" ? `where ${cmd}` : `command -v ${cmd}`;
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
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
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

function configDir(platform) {
  if (platform === "windows") {
    return path.join(process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming"), "claude");
  }
  return path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config"), "claude");
}

function cacheDir(platform) {
  if (platform === "windows") {
    return path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local"), "claude");
  }
  return path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache"), "claude");
}

// ============================================================================
// env.sh template
// ============================================================================
function envTemplate(remoteUrl) {
  return `#!/usr/bin/env bash
# ~/.config/claude/env.sh — Thin bootstrap for Claude Code environment
#
# This file fetches and caches the full configuration from a central URL.
# DO NOT put configuration logic here — edit the remote source instead.
#
# Update:   rm ~/.cache/claude/env-remote.sh  (or wait for TTL expiry)
# Debug:    CLAUDE_DEBUG=1 claude

# ── Remote source URL ─────────────────────────────────────────────────────────
CLAUDE_ENV_REMOTE_URL="\${CLAUDE_ENV_URL:-${remoteUrl}}"

# ── Cache settings ────────────────────────────────────────────────────────────
_CLAUDE_CACHE_DIR="\${XDG_CACHE_HOME:-\$HOME/.cache}/claude"
_CLAUDE_CACHE_FILE="\$_CLAUDE_CACHE_DIR/env-remote.sh"
_CLAUDE_UPDATE_TTL="\${CLAUDE_ENV_UPDATE_TTL:-300}" # check every 5 minutes

# ── Helpers ───────────────────────────────────────────────────────────────────
_claude_needs_update() {
  [[ ! -f "\$_CLAUDE_CACHE_FILE" ]] && return 0
  local age
  age=\$((\$(date +%s) - \$(stat -f %m "\$_CLAUDE_CACHE_FILE" 2>/dev/null || stat -c %Y "\$_CLAUDE_CACHE_FILE" 2>/dev/null || echo 0)))
  [[ \$age -ge \$_CLAUDE_UPDATE_TTL ]]
}

_claude_fetch_env() {
  (umask 077; mkdir -p "\$_CLAUDE_CACHE_DIR")

  local tmp="\$_CLAUDE_CACHE_FILE.tmp.\$\$"
  if (umask 077; curl -fsSL --connect-timeout 3 --max-time 10 "\$CLAUDE_ENV_REMOTE_URL" -o "\$tmp") 2>/dev/null; then
    mv "\$tmp" "\$_CLAUDE_CACHE_FILE"
  else
    rm -f "\$tmp"
    if [[ ! -f "\$_CLAUDE_CACHE_FILE" ]]; then
      echo "ERROR: Cannot fetch Claude env from \$CLAUDE_ENV_REMOTE_URL (no cache)" >&2
      return 1
    fi
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
if _claude_needs_update; then
  _claude_fetch_env
fi

if [[ -f "\$_CLAUDE_CACHE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "\$_CLAUDE_CACHE_FILE" "\$@"
fi

unset -f _claude_needs_update _claude_fetch_env
unset _CLAUDE_CACHE_DIR _CLAUDE_CACHE_FILE _CLAUDE_UPDATE_TTL
`;
}

// ============================================================================
// Installation
// ============================================================================
async function install(platform) {
  const cfgDir = configDir(platform);
  const cchDir = cacheDir(platform);
  const envFile = path.join(cfgDir, "env.sh");

  info(`Platform: ${platform}`);
  info(`Config:   ${cfgDir}`);

  // Create directories with correct permissions from the start
  fs.mkdirSync(cfgDir, { recursive: true, mode: 0o755 });
  fs.mkdirSync(cchDir, { recursive: true, mode: 0o700 });
  // Ensure cache dir permissions are correct (mkdirSync may not set mode on existing dirs)
  try { fs.chmodSync(cchDir, 0o700); } catch {}

  // Handle existing env.sh
  if (fs.existsSync(envFile) && process.env.CLAUDE_FORCE !== "1") {
    const stat = fs.lstatSync(envFile);
    if (stat.isSymbolicLink()) {
      warn(`${envFile} is a symlink (likely managed by stow)`);
      warn("Remove it first or set CLAUDE_FORCE=1 to overwrite");
      die("Aborting to avoid breaking your dotfiles setup");
    }

    const backup = `${envFile}.backup.${Date.now()}`;
    fs.copyFileSync(envFile, backup);
    info(`Backed up existing env.sh to ${backup}`);
  }

  // Write the thin bootstrap
  fs.writeFileSync(envFile, envTemplate(REMOTE_ENV_URL), { mode: 0o600 });
  ok(`Wrote ${envFile}`);

  // Pre-fetch the remote env to validate connectivity
  info("Fetching remote configuration...");
  try {
    const remoteEnv = await fetch(REMOTE_ENV_URL);
    const cachePath = path.join(cchDir, "env-remote.sh");
    fs.writeFileSync(cachePath, remoteEnv, { mode: 0o600 });
    ok("Remote configuration cached");
  } catch (err) {
    warn(`Could not fetch remote configuration: ${err.message}`);
    warn(`  URL: ${REMOTE_ENV_URL}`);
    warn("The bootstrap will retry on next Claude invocation");
  }
}

// ============================================================================
// Prerequisites
// ============================================================================
function checkPrerequisites() {
  if (!commandExists("curl")) {
    die("curl is required (used by the env.sh bootstrap for fetching updates)");
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
  if (platform === "unknown") {
    die(`Unsupported platform: ${process.platform}`);
  }

  checkPrerequisites();
  await install(platform);

  ok("Installation complete!");
  console.error("");
  console.error("  Claude Code will automatically source ~/.config/claude/env.sh");
  console.error("  which fetches the latest config from:");
  console.error(`    ${REMOTE_ENV_URL}`);
  console.error("");
  console.error("  Commands:");
  console.error("    Force refresh:  rm ~/.cache/claude/env-remote.sh");
  console.error("    Clear all:      source ~/.config/claude/env.sh --clear-cache");
  console.error("    Debug mode:     CLAUDE_DEBUG=1 claude");
  console.error("");
}

main().catch((err) => die(err.message));
