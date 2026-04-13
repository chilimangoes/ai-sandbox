[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$entrypoint = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 't3 serve --host 0\.0\.0\.0 --port') {
    throw "Expected docker/entrypoint.sh to invoke the installed t3 binary with the serve subcommand."
}

if ($entrypoint -match 'npx --yes t3') {
    throw "docker/entrypoint.sh still relies on npx for T3 startup."
}

Write-Host "t3-command.ps1 passed"
