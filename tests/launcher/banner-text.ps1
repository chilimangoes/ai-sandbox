[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$banner = Get-Content (Join-Path $repoRoot "configs\shared\banner.txt") -Raw
$entrypoint = Get-Content (Join-Path $repoRoot "docker\entrypoint.sh") -Raw

if ($banner -notmatch 'Run ai-sandbox t3 to start T3\.') {
    throw "Expected banner.txt to tell users to run ai-sandbox t3 before opening the T3 URL."
}

if ($entrypoint -notmatch 'Run ai-sandbox t3 to start T3\.') {
    throw "Expected docker/entrypoint.sh banner output to include a T3 start hint."
}

if ($banner -notmatch 'opencode') {
    throw "Expected banner.txt to mention opencode in the available commands list."
}

if ($entrypoint -notmatch 'opencode') {
    throw "Expected docker/entrypoint.sh to mention opencode in the shell banner or dispatch logic."
}

if ($banner -notmatch 'codenomad') {
    throw "Expected banner.txt to mention codenomad in the available commands list."
}

if ($entrypoint -notmatch 'Run ai-sandbox codenomad to start CodeNomad\.') {
    throw "Expected docker/entrypoint.sh banner output to include a CodeNomad start hint."
}

Write-Host "banner-text.ps1 passed"
