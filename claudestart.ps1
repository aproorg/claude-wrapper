# claudestart.ps1 — Process wrapper for Claude Code (Windows)
# Fetches remote config, sets up environment, and launches Claude Code.
#
# Install:  Copy to a directory on your PATH (e.g., C:\Users\YOU\bin)
# Update:   Remove-Item "$env:LOCALAPPDATA\claude\env-remote.ps1"
# Debug:    $env:CLAUDE_DEBUG = "1"; claudestart

# ============================================================================
# Configuration (mirrored from claude-env.sh)
# ============================================================================
$LiteLLM_BaseURL = "https://litellm.ai.apro.is"
$OP_Account = "aproorg.1password.eu"
$OP_Item = "op://Employee/ai.apro.is litellm"

# ── Local overrides (from local.env written by install.js) ───────────────────
$_LocalEnvPath = Join-Path ($env:APPDATA ?? (Join-Path $env:USERPROFILE "AppData\Roaming")) "claude\local.env"
if (Test-Path $_LocalEnvPath) {
    foreach ($line in Get-Content $_LocalEnvPath) {
        if ($line -match '^(LITELLM_BASE_URL|OP_ITEM)="(.*)"') {
            switch ($Matches[1]) {
                "LITELLM_BASE_URL" { $LiteLLM_BaseURL = $Matches[2] }
                "OP_ITEM"          { $OP_Item = $Matches[2] }
            }
        }
    }
}
Remove-Variable _LocalEnvPath -ErrorAction SilentlyContinue

$Model_Opus = "claude-opus-4-6"
$Model_Sonnet = "sonnet"
$Model_Haiku = "haiku"

$CacheTTL_Seconds = 43200  # 12 hours for API keys

# ============================================================================
# Cache directory
# ============================================================================
$CacheDir = Join-Path ($env:LOCALAPPDATA ?? (Join-Path $env:USERPROFILE "AppData\Local")) "claude"
if (-not (Test-Path $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
}

# ============================================================================
# Handle --clear-cache
# ============================================================================
if ($args -contains "--clear-cache") {
    Get-ChildItem -Path $CacheDir -Filter "*.key" -ErrorAction SilentlyContinue | Remove-Item -Force
    $RemoteCache = Join-Path $CacheDir "env-remote.ps1"
    if (Test-Path $RemoteCache) { Remove-Item $RemoteCache -Force }
    Write-Host "Claude env + API key cache cleared" -ForegroundColor Yellow
    exit 0
}

# ============================================================================
# Project Detection
# ============================================================================
function Sanitize-Name {
    param([string]$Name)
    # Strip anything except alphanumeric, hyphen, underscore, dot
    return ($Name -replace '[^a-zA-Z0-9_.\-]', '')
}

function Get-ClaudeProject {
    $raw = ""

    if ($env:CLAUDE_PROJECT) {
        $raw = $env:CLAUDE_PROJECT
    } else {
        # Try git remote name
        try {
            $remote = git remote get-url origin 2>$null
            if ($remote) {
                $raw = ($remote -split "/" | Select-Object -Last 1) -replace "\.git$", ""
            }
        } catch {}

        # Fall back to current directory name
        if (-not $raw) { $raw = (Split-Path -Leaf (Get-Location)) }
    }

    return (Sanitize-Name $raw)
}

# ============================================================================
# API Key Management
# ============================================================================
function Get-ApiKey {
    param([string]$Project)

    $cacheFile = Join-Path $CacheDir "$Project.key"

    # Check cache
    if (Test-Path $cacheFile) {
        $age = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
        if ($age.TotalSeconds -lt $CacheTTL_Seconds) {
            return (Get-Content $cacheFile -Raw).Trim()
        }
    }

    $key = $null

    # Try project-specific field first
    try {
        $key = & op --account $OP_Account read "$OP_Item/$Project" 2>$null
    } catch {}

    # Fall back to default "API Key" field
    if (-not $key) {
        try {
            $key = & op --account $OP_Account read "$OP_Item/API Key" 2>$null
        } catch {}

        if ($key -and $env:CLAUDE_DEBUG -eq "1") {
            Write-Host "Note: No key for project '$Project', using default" -ForegroundColor Yellow
        }
    }

    if (-not $key) {
        Write-Host "ERROR: Failed to retrieve API key from 1Password" -ForegroundColor Red
        return $null
    }

    # Cache
    $key | Out-File -FilePath $cacheFile -NoNewline -Encoding UTF8
    return $key
}

# ============================================================================
# Main
# ============================================================================
$Project = Get-ClaudeProject

# Base configuration
$env:ANTHROPIC_BASE_URL = $LiteLLM_BaseURL
$env:ANTHROPIC_MODEL = if ($env:CLAUDE_MODEL) { $env:CLAUDE_MODEL } else { $Model_Opus }
$env:ANTHROPIC_SMALL_FAST_MODEL = $Model_Haiku
$env:CLAUDE_CODE_SUBAGENT_MODEL = $Model_Haiku

# Feature flags
$env:CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS = "1"
$env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"

# API key
$apiKey = Get-ApiKey -Project $Project
if ($apiKey) {
    $env:ANTHROPIC_AUTH_TOKEN = $apiKey
} else {
    Write-Host "Warning: Could not retrieve Claude API key" -ForegroundColor Yellow
}

# Export project
$env:CLAUDE_PROJECT = $Project

if ($env:CLAUDE_DEBUG -eq "1") {
    Write-Host "Claude: project=$Project base=$LiteLLM_BaseURL model=$($env:ANTHROPIC_MODEL)" -ForegroundColor Cyan
}

# Launch Claude Code (pass through any arguments)
& claude @args
