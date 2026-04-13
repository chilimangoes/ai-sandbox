[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$entrypoint = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 'Connection string: \$AI_SANDBOX_T3_URL') {
    throw "Expected docker/entrypoint.sh to rewrite the T3 connection string to the host-visible URL."
}

if ($entrypoint -notmatch 'Pairing URL: \$AI_SANDBOX_T3_URL/pair#token=\$token') {
    throw "Expected docker/entrypoint.sh to rewrite the T3 pairing URL to the host-visible URL."
}

Write-Host "t3-output.ps1 passed"
