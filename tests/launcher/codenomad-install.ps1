[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dockerfile = Get-Content (Join-Path $repoRoot "Dockerfile") -Raw
$smoke = Get-Content (Join-Path $repoRoot "tests\smoke\image-smoke-check.sh") -Raw

if ($dockerfile -notmatch '@neuralnomads/codenomad') {
    throw "Expected Dockerfile to install CodeNomad in the image."
}

if ($smoke -notmatch 'codenomad --version') {
    throw "Expected smoke image check to verify the CodeNomad CLI."
}

Write-Host "codenomad-install.ps1 passed"
