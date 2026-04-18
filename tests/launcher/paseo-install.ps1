[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dockerfile = Get-Content (Join-Path $repoRoot "Dockerfile") -Raw
$smoke = Get-Content (Join-Path $repoRoot "tests\smoke\image-smoke-check.sh") -Raw
$paseoConfig = Get-Content (Join-Path $repoRoot "configs\paseo\config.json") -Raw

if ($dockerfile -notmatch '@getpaseo/cli') {
    throw "Expected Dockerfile to install the Paseo CLI."
}

if ($smoke -notmatch 'paseo --version') {
    throw "Expected the smoke image check to verify the Paseo CLI."
}

if ($paseoConfig -match '"\$schema"') {
    throw "Expected configs/paseo/config.json to omit the unsupported `$schema key for the installed Paseo CLI."
}

Write-Host "paseo-install.ps1 passed"
