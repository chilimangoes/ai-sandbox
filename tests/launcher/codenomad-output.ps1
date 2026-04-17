[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$entrypoint = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 'Starting CodeNomad on \$HOST_CODENOMAD_URL') {
    throw "Expected docker/entrypoint.sh to print the host-visible CodeNomad URL."
}

if ($entrypoint -notmatch 'Local Connection URL : \$AI_SANDBOX_CODENOMAD_URL') {
    throw "Expected docker/entrypoint.sh to rewrite CodeNomad local URLs to the host-visible URL."
}

Write-Host "codenomad-output.ps1 passed"
