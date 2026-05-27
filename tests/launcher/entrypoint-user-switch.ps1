[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$entrypoint = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 'run_as_root\(\)') {
    throw "Expected docker/entrypoint.sh to dispatch tool commands as root."
}

if ($entrypoint -match 'runuser\s+-u\s+sandbox\s+--') {
    throw "docker/entrypoint.sh still dispatches tool commands through the unprivileged sandbox user."
}

if ($entrypoint -match 'exec su -s /bin/bash sandbox -c') {
    throw "docker/entrypoint.sh still uses su for sandbox shell dispatch."
}

if ($entrypoint -notmatch 'export HOME=/home/sandbox') {
    throw "Expected root-dispatched commands to keep using the persisted sandbox home directory."
}

if ($entrypoint -notmatch 'git config --system --add safe\.directory ''\*''') {
    throw "Expected docker/entrypoint.sh to trust bind-mounted workspace repositories inside the sandbox."
}

Write-Host "entrypoint-user-switch.ps1 passed"
