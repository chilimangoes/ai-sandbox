[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$entrypoint = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 'runuser\s+-u\s+sandbox\s+--') {
    throw "Expected docker/entrypoint.sh to use runuser for sandbox shell dispatch."
}

if ($entrypoint -match 'exec su -s /bin/bash sandbox -c') {
    throw "docker/entrypoint.sh still uses su for sandbox shell dispatch."
}

Write-Host "entrypoint-user-switch.ps1 passed"
