# install.ps1 — Windows installer for claude-wrapper
#
# Usage:
#   irm https://raw.githubusercontent.com/aproorg/claude-wrapper/main/install.ps1 | iex
#
# Override base URL (test from a branch):
#   $env:CLAUDE_ENV_URL = "https://raw.githubusercontent.com/aproorg/claude-wrapper/<branch>/claude-env.sh"
#   irm https://raw.githubusercontent.com/aproorg/claude-wrapper/<branch>/install.ps1 | iex
#
# Options:
#   $env:CLAUDE_FORCE = "1"   Overwrite existing wrapper without backup

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ── Output helpers ──────────────────────────────────────────────────────────
function Write-Info($msg) { Write-Host "  [INFO]  $msg" -ForegroundColor Blue }
function Write-Ok($msg)   { Write-Host "  [OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  [ERROR] $msg" -ForegroundColor Red; exit 1 }

# ── Configuration ───────────────────────────────────────────────────────────
$DefaultBase = "https://raw.githubusercontent.com/aproorg/claude-wrapper/main"

# Derive base URL from CLAUDE_ENV_URL (so branch installs propagate)
if ($env:CLAUDE_ENV_URL) {
    $RemoteEnvUrl = $env:CLAUDE_ENV_URL
    $BaseUrl = $env:CLAUDE_ENV_URL -replace '/claude-env\.sh$', ''
} else {
    $BaseUrl = $DefaultBase
    $RemoteEnvUrl = "$BaseUrl/claude-env.sh"
}

$InstallDir = "$env:LOCALAPPDATA\Programs\claude-wrapper"
$ConfigDir  = "$env:APPDATA\claude"
$CacheDir   = "$env:LOCALAPPDATA\claude"
$Ps1Path    = "$InstallDir\claudestart.ps1"
$CmdPath    = "$InstallDir\claudestart.cmd"
$LocalEnv   = "$ConfigDir\local.env"
$RemoteCache = "$CacheDir\env-remote.sh"

# ── Prerequisites ───────────────────────────────────────────────────────────
function Have($cmd) {
    $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Check-Prerequisites {
    if (-not (Have 'powershell')) { Write-Err "PowerShell is required" }
    if (-not (Have 'op')) {
        Write-Warn "1Password CLI (op) not found — API key management will not work."
        Write-Warn "Install: https://developer.1password.com/docs/cli/get-started/"
    }
    if (-not (Have 'git')) {
        Write-Warn "git not found — project detection will fall back to directory name"
    }
}

# ── PATH management ─────────────────────────────────────────────────────────
function Ensure-OnPath($dir) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $normalized = ($userPath -split ';' | ForEach-Object { $_.TrimEnd('\').ToLower() })
    if ($normalized -contains $dir.TrimEnd('\').ToLower()) {
        Write-Ok "$dir is already on user PATH"
        return
    }
    $newPath = if ($userPath) { "$userPath;$dir" } else { $dir }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Ok "Added $dir to user PATH"
    Write-Warn "Restart your terminal for PATH changes to take effect"
}

# ── Interactive prompts ─────────────────────────────────────────────────────
function Prompt-Default($question, $default) {
    # When run via `irm | iex` the script body executes in the current PowerShell
    # session, so Read-Host has access to the user's terminal. If the host has
    # been redirected (CI, scripted invocation), fall back to default silently.
    if ([Console]::IsInputRedirected) { return $default }
    $reply = Read-Host "  $question [$default]"
    if ([string]::IsNullOrWhiteSpace($reply)) { return $default }
    return $reply.Trim()
}

function Read-Existing($key) {
    if (-not (Test-Path $LocalEnv)) { return "" }
    foreach ($line in Get-Content $LocalEnv) {
        if ($line -match "^$key=`"(.*)`"$") { return $Matches[1] }
    }
    return ""
}

function Prompt-LocalConfig {
    Write-Host ""
    Write-Info "Configure your local connection settings:"
    Write-Host ""

    $currentUrl  = Read-Existing 'LITELLM_BASE_URL'
    $currentItem = Read-Existing 'OP_ITEM'

    $defaultUrl  = if ($currentUrl)  { $currentUrl }  else { "https://litellm.ai.apro.is" }
    $defaultItem = if ($currentItem) { $currentItem } else { "op://Employee/ai.apro.is litellm" }

    $litellmUrl = Prompt-Default "LiteLLM base URL" $defaultUrl

    while ($true) {
        $opItem = Prompt-Default "1Password item (op://...)" $defaultItem
        if ($opItem -like 'op://*') { break }
        Write-Warn "Must start with op:// — try again"
    }

    $content = @"
# Local overrides — User-specific settings
# Written by install.ps1, sourced by claudestart.ps1
LITELLM_BASE_URL="$litellmUrl"
OP_ITEM="$opItem"
"@
    Set-Content -Path $LocalEnv -Value $content -Encoding UTF8
    Write-Ok "Wrote $LocalEnv"
}

# ── Fetch + patch the wrapper script ────────────────────────────────────────
function Fetch-Wrapper {
    # Bake the chosen RemoteEnvUrl into the wrapper as the default, so a
    # branch-installed wrapper keeps fetching from that branch without needing
    # CLAUDE_ENV_URL re-exported.
    $defaultLine = '$_RemoteUrl = if ($env:CLAUDE_ENV_URL) { $env:CLAUDE_ENV_URL } else { "https://raw.githubusercontent.com/aproorg/claude-wrapper/main/claude-env.sh" }'
    $patchedLine = "`$_RemoteUrl = if (`$env:CLAUDE_ENV_URL) { `$env:CLAUDE_ENV_URL } else { `"$RemoteEnvUrl`" }"

    $content = Invoke-WebRequest -Uri "$BaseUrl/claudestart.ps1" -UseBasicParsing -TimeoutSec 30 |
               Select-Object -ExpandProperty Content
    return $content.Replace($defaultLine, $patchedLine)
}

function Backup-Existing {
    if (-not (Test-Path $Ps1Path)) { return }
    if ($env:CLAUDE_FORCE -eq "1") {
        Remove-Item $Ps1Path -Force
        Write-Info "Removed existing wrapper (CLAUDE_FORCE=1)"
        return
    }
    $backup = "$Ps1Path.backup.$([int][double]::Parse((Get-Date -UFormat %s)))"
    Copy-Item $Ps1Path $backup
    Write-Info "Backed up existing wrapper to $backup"
    Remove-Item $Ps1Path -Force
}

# ── Main ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Claude Code Environment Installer" -ForegroundColor White
Write-Host ("  " + ("─" * 35))
Write-Host ""

Check-Prerequisites

Write-Info "Install dir: $InstallDir"
Write-Info "Source:      $BaseUrl"

@($InstallDir, $ConfigDir, $CacheDir) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

Backup-Existing

Write-Info "Downloading claudestart.ps1..."
try {
    $content = Fetch-Wrapper
    Set-Content -Path $Ps1Path -Value $content -Encoding UTF8
    Write-Ok "Wrote $Ps1Path"
} catch {
    Write-Err "Failed to download claudestart.ps1: $($_.Exception.Message)"
}

# .cmd shim so users can type just `claudestart`
$shimContent = "@powershell -ExecutionPolicy Bypass -File `"%~dp0claudestart.ps1`" %*`r`n"
Set-Content -Path $CmdPath -Value $shimContent -Encoding ASCII -NoNewline
Write-Ok "Wrote $CmdPath"

Ensure-OnPath $InstallDir

Write-Info "Fetching remote configuration..."
try {
    Invoke-WebRequest -Uri $RemoteEnvUrl -OutFile $RemoteCache -UseBasicParsing -TimeoutSec 10
    Write-Ok "Remote configuration cached"
} catch {
    Write-Warn "Could not pre-fetch remote config (will be fetched on first launch)"
}

Prompt-LocalConfig

Write-Host ""
Write-Ok "Installation complete!"
Write-Host @"

  The claudestart command launches Claude Code with team config.

  Commands:
    Verify:         Get-Command claudestart
    Debug:          `$env:CLAUDE_DEBUG = "1"; claudestart
    Force refresh:  Remove-Item $RemoteCache

"@
