[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dockerfile = Get-Content (Join-Path $repoRoot "Dockerfile") -Raw
$smoke = Get-Content (Join-Path $repoRoot "tests\smoke\image-smoke-check.sh") -Raw

if ($dockerfile -notmatch '\blbzip2\b') {
    throw "Expected Dockerfile to install lbzip2 so Paseo can extract local speech model archives."
}

if ($smoke -notmatch 'command -v lbzip2') {
    throw "Expected the image smoke check to verify lbzip2 is available."
}

Write-Host "paseo-speech-model-dependencies.ps1 passed"
