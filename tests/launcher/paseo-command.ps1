[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$entrypoint = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 'paseo\)') {
    throw "Expected docker/entrypoint.sh to dispatch a paseo command."
}

if ($entrypoint -notmatch 'PASEO_HOME') {
    throw "Expected docker/entrypoint.sh to set PASEO_HOME before launching Paseo."
}

if ($entrypoint -notmatch 'paseo daemon start .*--foreground') {
    throw "Expected docker/entrypoint.sh to launch Paseo in foreground mode."
}

Write-Host "paseo-command.ps1 passed"
