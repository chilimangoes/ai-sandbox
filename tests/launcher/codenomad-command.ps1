[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$entrypoint = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 'codenomad .*--http=true .*--https=false') {
    throw "Expected docker/entrypoint.sh to run CodeNomad in HTTP-only server mode."
}

if ($entrypoint -notmatch '--workspace-root') {
    throw "Expected docker/entrypoint.sh to restrict CodeNomad to the sandbox workspace root."
}

if ($entrypoint -notmatch 'codenomad\)') {
    throw "Expected docker/entrypoint.sh to dispatch a codenomad command."
}

Write-Host "codenomad-command.ps1 passed"
