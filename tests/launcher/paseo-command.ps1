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

if ($entrypoint -notmatch 'paseo daemon run --home /state/data/paseo') {
    throw "Expected docker/entrypoint.sh to launch Paseo in foreground mode."
}

if ($entrypoint -notmatch "export PASEO_RELAY_ENABLED='\`$PASEO_RELAY_ENABLED'") {
    throw "Expected docker/entrypoint.sh to use the configured Paseo relay environment override."
}

if ($entrypoint -notmatch 'trap cleanup_paseo_daemon INT TERM EXIT') {
    throw "Expected docker/entrypoint.sh to clean up Paseo on interrupt and exit."
}

Write-Host "paseo-command.ps1 passed"
