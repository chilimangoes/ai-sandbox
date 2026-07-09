[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dockerfile = Get-Content (Join-Path $repoRoot "Dockerfile") -Raw

if ($dockerfile -notmatch 'curl -fsSL https://antigravity\.google/cli/install\.sh \| bash') {
    throw "Expected Dockerfile to install Antigravity CLI using the official install script."
}

if ($dockerfile -notmatch 'command -v agy') {
    throw "Expected Dockerfile to verify that the agy command is available before shimming it."
}

Write-Host "antigravity-install.ps1 passed"
