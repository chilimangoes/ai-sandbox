[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dockerfile = Get-Content (Join-Path $repoRoot "Dockerfile") -Raw
$entrypoint = Get-Content (Join-Path $repoRoot "docker\entrypoint.sh") -Raw
$bootstrap = Get-Content (Join-Path $repoRoot "docker\bootstrap\init-state.sh") -Raw
$bashLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox") -Raw
$powershellLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox.ps1") -Raw
$smoke = Get-Content (Join-Path $repoRoot "tests\smoke\image-smoke-check.sh") -Raw
$banner = Get-Content (Join-Path $repoRoot "configs\shared\banner.txt") -Raw
$claudeConfigPath = Join-Path $repoRoot "configs\claude\settings.json"

if (-not (Test-Path $claudeConfigPath)) {
    throw "Expected configs/claude/settings.json to provide valid default Claude user settings."
}

$claudeConfig = Get-Content $claudeConfigPath -Raw | ConvertFrom-Json

if ($bootstrap -notmatch '/state/config/claude/settings\.json') {
    throw "Expected bootstrap to expose Claude user settings from persisted config."
}

if ($dockerfile -notmatch '@anthropic-ai/claude-code') {
    throw "Expected Dockerfile to install the official Claude Code npm package."
}

if ($dockerfile -notmatch 'for command in .*claude') {
    throw "Expected Dockerfile to install an in-container shim for claude."
}

if ($entrypoint -notmatch 'echo "claude: \$\(claude --version') {
    throw "Expected doctor output to report Claude Code."
}

if ($entrypoint -notmatch '(?ms)claude\).*?/opt/ai-sandbox/claude-wrapper.sh "\$@"') {
    throw "Expected docker/entrypoint.sh to dispatch claude through the state wrapper and forward all arguments."
}

foreach ($path in @("/state/data/claude/home", "/state/data/claude/claude.json")) {
    if ($bootstrap -notmatch [regex]::Escape($path)) {
        throw "Expected bootstrap to configure persistent Claude state at $path."
    }
}

if ($smoke -notmatch 'claude --version') {
    throw "Expected the image smoke check to verify Claude Code."
}

if ($banner -notmatch 'claude') {
    throw "Expected the shared shell banner to mention Claude Code."
}

foreach ($launcher in @($bashLauncher, $powershellLauncher)) {
    if ($launcher -notmatch 'Usage: .*claude') {
        throw "Expected both host launcher usage strings to advertise claude."
    }
}

$documentation = @(
    "README.md",
    "docs\usage.md",
    "docs\auth.md",
    "docs\config-management.md",
    "docs\architecture.md",
    "docs\troubleshooting.md",
    "docs\manual-verification-checklist.md"
)

foreach ($relativePath in $documentation) {
    $content = Get-Content (Join-Path $repoRoot $relativePath) -Raw
    if ($content -notmatch '(?i)claude') {
        throw "Expected $relativePath to document Claude Code."
    }
}

Write-Host "claude-install.ps1 passed"
