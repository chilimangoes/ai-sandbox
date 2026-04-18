[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$entrypoint = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 'Starting Paseo on \$HOST_PASEO_ADDRESS') {
    throw "Expected docker/entrypoint.sh to print the host-visible Paseo daemon address."
}

Write-Host "paseo-output.ps1 passed"
