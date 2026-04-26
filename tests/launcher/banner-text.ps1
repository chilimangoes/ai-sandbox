[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$banner = Get-Content (Join-Path $repoRoot "configs\shared\banner.txt") -Raw
$entrypoint = Get-Content (Join-Path $repoRoot "docker\entrypoint.sh") -Raw

if ($banner -notmatch 'Run ai-sandbox t3 to start T3\.') {
    throw "Expected banner.txt to tell users to run ai-sandbox t3 before opening the T3 URL."
}

if ($entrypoint -notmatch 'banner\.txt') {
    throw "Expected docker/entrypoint.sh banner output to include the shared banner text."
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

if ($entrypoint -notmatch 'banner\.txt') {
    throw "Expected docker/entrypoint.sh banner output to include the shared banner text."
}

if ($banner -notmatch 'paseo') {
    throw "Expected banner.txt to mention paseo in the available commands list."
}

if ($entrypoint -notmatch 'banner\.txt') {
    throw "Expected docker/entrypoint.sh banner output to include the shared banner text."
}

if ($entrypoint -notmatch 'Web Port 80: %s') {
    throw "Expected docker/entrypoint.sh to print the host-visible mapping for container port 80 in the shell banner."
}

if ($entrypoint -notmatch 'Web Port 8080: %s') {
    throw "Expected docker/entrypoint.sh to print the host-visible mapping for container port 8080 in the shell banner."
}

if ($entrypoint -notmatch 'Web Port 3000: %s') {
    throw "Expected docker/entrypoint.sh to print the host-visible mapping for container port 3000 in the shell banner."
}

Write-Host "banner-text.ps1 passed"
