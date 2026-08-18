[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dockerfile = Get-Content (Join-Path $repoRoot "Dockerfile") -Raw
$entrypoint = Get-Content (Join-Path $repoRoot "docker\entrypoint.sh") -Raw
$bootstrap = Get-Content (Join-Path $repoRoot "docker\bootstrap\init-state.sh") -Raw
$usage = Get-Content (Join-Path $repoRoot "docs\usage.md") -Raw
$auth = Get-Content (Join-Path $repoRoot "docs\auth.md") -Raw
$configManagement = Get-Content (Join-Path $repoRoot "docs\config-management.md") -Raw
$cursorConfigPath = Join-Path $repoRoot "configs\cursor\cli-config.json"

if (-not (Test-Path $cursorConfigPath)) {
    throw "Expected configs/cursor/cli-config.json to provide Cursor YOLO defaults."
}

$expectedCursorConfig = [ordered]@{
    permissions = [ordered]@{ allow = @(); deny = @() }
    version = 1
    modelSlashCommands = $false
    rewind = $true
    hasChangedDefaultModel = $false
    approvalMode = "unrestricted"
    autoAcceptWebSearch = $true
} | ConvertTo-Json -Depth 4 -Compress
$actualCursorConfig = (Get-Content $cursorConfigPath -Raw | ConvertFrom-Json) |
    ConvertTo-Json -Depth 4 -Compress
if ($actualCursorConfig -ne $expectedCursorConfig) {
    throw "Cursor default config does not exactly match the requested YOLO preset."
}

if ($dockerfile -notmatch 'curl https://cursor\.com/install -fsS \| bash') {
    throw "Expected Dockerfile to install Cursor CLI using the official installer."
}

if ($dockerfile -notmatch '(?s)command -v cursor-agent.*for command in .*cursor-agent') {
    throw "Expected Dockerfile to verify cursor-agent before creating command shims."
}

if ($dockerfile -notmatch 'AI_SANDBOX_REAL_BIN_DIR/cursor-agent') {
    throw "Expected Dockerfile to retain cursor-agent as the canonical real binary."
}

foreach ($command in @("cursor-agent", "cursor")) {
    if ($dockerfile -notmatch "for command in .*${command}") {
        throw "Expected Dockerfile to install an in-container shim for $command."
    }
}

if ($entrypoint -notmatch '(?ms)run_cursor_as_root\(\).*?AGENT_CLI_CREDENTIAL_STORE=file') {
    throw "Expected Cursor commands to use Cursor's file credential store."
}

if ($entrypoint -notmatch '(?ms)run_cursor_as_root\(\).*?/opt/ai-sandbox/bin/cursor-agent') {
    throw "Expected the Cursor credential wrapper to invoke the real cursor-agent binary."
}

foreach ($command in @("cursor", "cursor-agent")) {
    if ($entrypoint -notmatch "(?ms)${command}\).*?run_cursor_as_root") {
        throw "Expected $command to dispatch through the persistent credential wrapper."
    }
}

if ($entrypoint -notmatch 'echo "cursor: \$\(cursor --version') {
    throw "Expected doctor output to report the Cursor CLI through the cursor alias."
}

if ($bootstrap -notmatch '/state/data/cursor') {
    throw "Expected bootstrap to create persistent Cursor state."
}

if ($bootstrap -notmatch '/state/config/cursor') {
    throw "Expected bootstrap to create the persisted Cursor config directory."
}

if ($bootstrap -notmatch 'ln -sfn /state/config/cursor/cli-config\.json /state/data/cursor/cli-config\.json') {
    throw "Expected bootstrap to expose the persisted Cursor config through Cursor's runtime home."
}

if ($bootstrap -notmatch '(?s)-f /state/data/cursor/cli-config\.json.*! -L /state/data/cursor/cli-config\.json.*mv /state/data/cursor/cli-config\.json /state/config/cursor/cli-config\.json') {
    throw "Expected bootstrap to migrate a legacy regular Cursor config before linking it."
}

if ($bootstrap -notmatch 'ln -sfn /state/data/cursor /home/sandbox/\.cursor') {
    throw "Expected bootstrap to link Cursor home state into the data volume."
}

if ($bootstrap -notmatch '/state/auth/cursor') {
    throw "Expected bootstrap to create persistent Cursor authentication state."
}

if ($bootstrap -notmatch 'ln -sfn /state/auth/cursor /home/sandbox/\.config/cursor') {
    throw "Expected bootstrap to link Cursor's file credential store into the auth volume."
}

foreach ($name in @("cursor", "cursor-agent")) {
    if ($usage -notmatch [regex]::Escape($name)) {
        throw "Expected docs/usage.md to document $name."
    }
}

foreach ($path in @("/state/auth/cursor", "/state/data/cursor")) {
    if ($auth -notmatch [regex]::Escape($path)) {
        throw "Expected docs/auth.md to document persisted Cursor state at $path."
    }
}

foreach ($term in @("approvalMode", "autoAcceptWebSearch", "/state/config/cursor/cli-config.json", "reset-config", "reset-state")) {
    if ($configManagement -notmatch [regex]::Escape($term)) {
        throw "Expected docs/config-management.md to document Cursor config behavior for $term."
    }
}

if ($auth -notmatch '/state/config/cursor/cli-config\.json') {
    throw "Expected docs/auth.md to distinguish Cursor config from runtime state."
}

if ($usage -notmatch 'unrestricted approvals' -or $usage -notmatch 'automatic web-search acceptance') {
    throw "Expected docs/usage.md to describe Cursor's default YOLO behavior."
}

Write-Host "cursor-install.ps1 passed"
