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
# Field name used as the API-key fallback when no project-specific field exists.
# Overridable via OP_FIELD in local.env for users with non-standard field names.
$OP_Field = "API Key"

$Model_Opus = "claude-opus-4-6"
$Model_Sonnet = "sonnet"
$Model_Haiku = "haiku"

$CacheTTL_Seconds = 43200  # 12 hours for API keys
$ConfigTTL_Seconds = 300   # 5 minutes for remote config

# ============================================================================
# Cache directory
# ============================================================================
$CacheDir = "$env:LOCALAPPDATA\claude"
if (-not (Test-Path $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
}

# ============================================================================
# Handle --clear-cache
# ============================================================================
if ($args -contains "--clear-cache") {
    Get-ChildItem -Path $CacheDir -Filter "*.key" -ErrorAction SilentlyContinue | Remove-Item -Force
    $RemoteCache = Join-Path $CacheDir "env-remote.sh"
    if (Test-Path $RemoteCache) { Remove-Item $RemoteCache -Force }
    Write-Host "Claude env + API key cache cleared" -ForegroundColor Yellow
    exit 0
}

# ============================================================================
# Remote config fetch + cache
# ============================================================================
$_RemoteUrl = if ($env:CLAUDE_ENV_URL) { $env:CLAUDE_ENV_URL } else { "https://raw.githubusercontent.com/aproorg/claude-wrapper/main/claude-env.sh" }
$_RemoteCache = Join-Path $CacheDir "env-remote.sh"

$_NeedsFetch = $true
if (Test-Path $_RemoteCache) {
    $_Age = ((Get-Date) - (Get-Item $_RemoteCache).LastWriteTime).TotalSeconds
    if ($_Age -lt $ConfigTTL_Seconds) { $_NeedsFetch = $false }
}

if ($_NeedsFetch) {
    try {
        $_tmp = "$_RemoteCache.tmp.$PID"
        Invoke-WebRequest -Uri $_RemoteUrl -OutFile $_tmp -TimeoutSec 10 -ErrorAction Stop
        # Integrity check: reject dangerous patterns
        $_content = Get-Content $_tmp -Raw
        if ($_content -match '(rm\s+-rf\s+/|curl.*\|\s*(ba)?sh|eval\s)') {
            [Console]::Error.WriteLine("ERROR: Remote config failed integrity check")
            Remove-Item $_tmp -Force -ErrorAction SilentlyContinue
            exit 1
        }
        Move-Item $_tmp $_RemoteCache -Force
    } catch {
        Remove-Item "$_RemoteCache.tmp.$PID" -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $_RemoteCache)) {
            [Console]::Error.WriteLine("ERROR: Cannot fetch config from $_RemoteUrl (no cache)")
            exit 1
        }
        if ($env:CLAUDE_DEBUG -eq "1") {
            $_StaleAge = [int]((Get-Date) - (Get-Item $_RemoteCache).LastWriteTime).TotalSeconds
            [Console]::Error.WriteLine("Warning: Using stale cached config (${_StaleAge}s old, fetch failed)")
        }
    }
}

# Parse remote config for key overrides (remote defaults -> local overrides)
if (Test-Path $_RemoteCache) {
    foreach ($_line in Get-Content $_RemoteCache) {
        if ($_line -match '^\s*(?:export\s+)?(\w+)="(.*?)"\s*$') {
            switch ($Matches[1]) {
                "LITELLM_BASE_URL" { $LiteLLM_BaseURL = $Matches[2] }
                "OP_ACCOUNT"       { $OP_Account = $Matches[2] }
                "OP_ITEM"          { $OP_Item = $Matches[2] }
            }
        }
    }
}
Remove-Variable _RemoteUrl, _RemoteCache, _NeedsFetch, _Age, _tmp, _content, _StaleAge, _line -ErrorAction SilentlyContinue

# ── Local overrides (from local.env written by install.js) ───────────────────
$_LocalEnvPath = "$env:APPDATA\claude\local.env"
if (Test-Path $_LocalEnvPath) {
    foreach ($line in Get-Content $_LocalEnvPath) {
        if ($line -match '^(LITELLM_BASE_URL|OP_ITEM|OP_FIELD|OP_ACCOUNT)="(.*)"') {
            switch ($Matches[1]) {
                "LITELLM_BASE_URL" { $LiteLLM_BaseURL = $Matches[2] }
                "OP_ITEM"          { $OP_Item = $Matches[2] }
                "OP_FIELD"         { $OP_Field = $Matches[2] }
                "OP_ACCOUNT"       { $OP_Account = $Matches[2] }
            }
        }
    }
}
Remove-Variable _LocalEnvPath -ErrorAction SilentlyContinue

# Defensive migration: legacy local.env files set OP_ITEM with the field baked
# into the path (e.g. op://V/Item/API Key). Post-#13, OP_FIELD is separate and
# the wrapper appends it itself, so a legacy 3+ segment OP_ITEM would yield
# bogus lookups like op://V/Item/API Key/API Key. Split silently — a 1Password
# item path is always exactly Vault/Item; anything beyond is the field.
if ($OP_Item) {
    $_opStripped = $OP_Item -replace '^op://', ''
    $_opSegs = $_opStripped.Split('/')
    if ($_opSegs.Count -gt 2) {
        $OP_Item = "op://$($_opSegs[0])/$($_opSegs[1])"
        $OP_Field = ($_opSegs | Select-Object -Skip 2) -join '/'
    }
    Remove-Variable _opStripped, _opSegs -ErrorAction SilentlyContinue
}

# ============================================================================
# Project Detection
# ============================================================================
function Sanitize-Name {
    param([string]$Name)
    # Strip anything except alphanumeric, hyphen, underscore, dot; strip leading dots
    $cleaned = ($Name -replace '[^a-zA-Z0-9_.\-]', '') -replace '^\.+', ''
    if (-not $cleaned) { return 'unnamed' }
    return $cleaned
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

# Returns "org/repo" from git origin (e.g. "aproorg/claude-wrapper"), or empty
# string if not derivable. Used for the x-github-repo header so LiteLLM can
# attribute usage per-repo. Slashes are intentional here — it's a header
# value, not a filename or 1P field name. Override via CLAUDE_GITHUB_REPO.
function Get-GitHubRepo {
    if ($env:CLAUDE_GITHUB_REPO) { return $env:CLAUDE_GITHUB_REPO }

    $url = ""
    try {
        $url = git remote get-url origin 2>$null
    } catch {}
    if (-not $url) { return "" }

    # Strip protocol+host (HTTPS) or user@host: (SSH).
    if ($url -match '://') {
        $url = $url -replace '^[^:]+://[^/]+/', ''
    } elseif ($url -match ':') {
        $url = $url -replace '^[^:]*:', ''
    }
    $url = $url -replace '\.git$', ''

    # Last two path components (handles GitLab subgroups: subgroup/project).
    $segs = $url.Split('/')
    if ($segs.Count -ge 2) {
        return "$($segs[$segs.Count - 2])/$($segs[$segs.Count - 1])"
    }
    return ""
}

# ============================================================================
# API Key Management
# ============================================================================
# Invoke `op read` for a path, capturing stdout and stderr separately.
# Returns a hashtable: @{ Key = <stdout-trimmed-or-null>; Err = <stderr> }.
function Invoke-OpRead {
    param([string]$Path)
    $stderrFile = [IO.Path]::GetTempFileName()
    try {
        try {
            $stdout = & op --account $OP_Account read $Path 2>$stderrFile
        } catch {
            return @{ Key = $null; Err = "op invocation failed: $($_.Exception.Message)" }
        }
        $stderr = (Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue) -replace '\s+$', ''
        $key = if ($stdout) { (@($stdout) -join "`n").Trim() } else { $null }
        return @{ Key = $key; Err = $stderr }
    } finally {
        Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-ApiKey {
    param([string]$Project)

    $cacheFile = Join-Path $CacheDir "$Project.key"

    # Check cache (file must exist and be non-empty)
    if ((Test-Path $cacheFile) -and (Get-Item $cacheFile).Length -gt 0) {
        $age = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
        if ($age.TotalSeconds -lt $CacheTTL_Seconds) {
            if ($env:CLAUDE_DEBUG -eq "1") { [Console]::Error.WriteLine("key=cached") }
            return (Get-Content $cacheFile -Raw).Trim()
        }
    }

    $key = $null
    $attempts = @()  # ordered list of @{ Path = ...; Err = ... } for diagnostics

    # Try project-specific field first
    $projectPath = "$OP_Item/$Project"
    $r = Invoke-OpRead $projectPath
    $attempts += @{ Path = $projectPath; Err = $r.Err }
    if ($r.Key) { $key = $r.Key }

    # Fall back to the configured fallback field (default "API Key", overridable
    # via OP_FIELD in local.env for users with non-standard 1Password field names)
    if (-not $key) {
        $defaultPath = "$OP_Item/$OP_Field"
        $r = Invoke-OpRead $defaultPath
        $attempts += @{ Path = $defaultPath; Err = $r.Err }
        if ($r.Key) {
            $key = $r.Key
            if ($env:CLAUDE_DEBUG -eq "1") {
                [Console]::Error.WriteLine("Note: No key for project '$Project', using default field '$OP_Field'")
            }
        }
    }

    if (-not $key) {
        [Console]::Error.WriteLine("ERROR: Failed to retrieve API key from 1Password")
        if ($env:CLAUDE_DEBUG -eq "1") {
            [Console]::Error.WriteLine("  account: $OP_Account")
            [Console]::Error.WriteLine("  paths tried (with op stderr):")
            foreach ($a in $attempts) {
                [Console]::Error.WriteLine("    - $($a.Path)")
                if ($a.Err) {
                    foreach ($line in ($a.Err -split "`r?`n")) {
                        if ($line) { [Console]::Error.WriteLine("        $line") }
                    }
                }
            }
            [Console]::Error.WriteLine("  Field name is case-sensitive (currently OP_FIELD='$OP_Field').")
            [Console]::Error.WriteLine("  Override via OP_FIELD in `$env:APPDATA\claude\local.env if needed.")
        } else {
            [Console]::Error.WriteLine("  Run with `$env:CLAUDE_DEBUG = `"1`" for op stderr details.")
        }
        return $null
    }

    # Cache (atomic: write to temp then rename)
    $tmpFile = "$cacheFile.tmp.$PID"
    $key | Out-File -FilePath $tmpFile -NoNewline -Encoding UTF8
    Move-Item $tmpFile $cacheFile -Force

    if ($env:CLAUDE_DEBUG -eq "1") { [Console]::Error.WriteLine("key=fetched") }
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
    [Console]::Error.WriteLine("Warning: Could not retrieve Claude API key")
}

# Export project
$env:CLAUDE_PROJECT = $Project

# Custom headers — auto-inject x-github-repo for LiteLLM per-repo attribution.
# Prefer the full org/repo from the git remote (e.g. "aproorg/claude-wrapper")
# and fall back to the simple sanitized project name when no remote is set.
# Appends to any pre-existing ANTHROPIC_CUSTOM_HEADERS (newline-separated per
# Claude Code docs) so user-defined headers are preserved.
$githubRepo = Get-GitHubRepo
$headerValue = if ($githubRepo) { $githubRepo } else { $Project }
$claudeHeader = "x-github-repo: $headerValue"
if ($env:ANTHROPIC_CUSTOM_HEADERS) {
    $env:ANTHROPIC_CUSTOM_HEADERS = "$($env:ANTHROPIC_CUSTOM_HEADERS)`n$claudeHeader"
} else {
    $env:ANTHROPIC_CUSTOM_HEADERS = $claudeHeader
}

if ($env:CLAUDE_DEBUG -eq "1") {
    [Console]::Error.WriteLine("Claude: project=$Project base=$LiteLLM_BaseURL model=$($env:ANTHROPIC_MODEL) headers=$($env:ANTHROPIC_CUSTOM_HEADERS)")
}

# Launch Claude Code (pass through any arguments)
& claude @args
