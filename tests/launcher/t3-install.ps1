[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$dockerfile = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "Dockerfile") -Raw

if ($dockerfile -notmatch '(?ms)\bmake\b') {
    throw "Expected Dockerfile to install make so T3 native dependencies can build."
}

if ($dockerfile -notmatch '(?ms)^\s*g\+\+\s*\\?$') {
    throw "Expected Dockerfile to install g++ so T3 native dependencies can build."
}

if ($dockerfile -notmatch 'npm install -g [^\r\n]*\bt3\b') {
    throw "Expected Dockerfile to install the t3 CLI in the image."
}

Write-Host "t3-install.ps1 passed"
