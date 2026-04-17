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

Write-Host "port-conflict-retry.ps1 passed"
