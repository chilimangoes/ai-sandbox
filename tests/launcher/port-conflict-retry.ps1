[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bashLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox") -Raw
$psLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox.ps1") -Raw

if ($bashLauncher.Contains("port is already allocated' -and -not $FORCE_RECREATE")) {
    throw "Expected bin/ai-sandbox to retry on port conflicts even during --rebuild."
}

if ($psLauncher.Contains("port is already allocated' -and -not $ForceRecreate")) {
    throw "Expected bin/ai-sandbox.ps1 to retry on port conflicts even during --rebuild."
}

if ($psLauncher -notmatch 'ports are not available') {
    throw "Expected bin/ai-sandbox.ps1 to retry on Docker's Windows port conflict message."
}

if ($psLauncher -notmatch 'IPAddress\]::Parse\("127\.0\.0\.1"\)') {
    throw "Expected bin/ai-sandbox.ps1 to probe the same loopback address used by Docker port publishing."
}

Write-Host "port-conflict-retry.ps1 passed"
