[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$launcherPath = Join-Path $repoRoot "bin\ai-sandbox.ps1"
$helperPath = Join-Path $repoRoot "scripts\add-supplemental-folder.ps1"

if (-not (Test-Path $helperPath)) {
    throw "Expected scripts/add-supplemental-folder.ps1 to manage supplemental folder config."
}

$launcher = Get-Content $launcherPath -Raw
$helper = Get-Content $helperPath -Raw

if ($launcher -notmatch '--add-folder') {
    throw "Expected PowerShell launcher usage/parsing to include --add-folder."
}

if ($launcher -notmatch 'Get-SupplementalFolderMounts') {
    throw "Expected PowerShell launcher to load supplemental folder mappings before docker run."
}

if ($launcher -notmatch 'supplemental-folders\.config') {
    throw "Expected PowerShell launcher to read supplemental folder mappings from supplemental-folders.config."
}

if ($launcher -notmatch 'ai-sandbox\.supplemental-folders') {
    throw "Expected PowerShell launcher to store a supplemental folder signature label on containers."
}

if ($launcher -notmatch '/supplemental/') {
    throw "Expected PowerShell launcher to mount supplemental folders under /supplemental."
}

if ($launcher -notmatch 'Write-Warning') {
    throw "Expected PowerShell launcher to use Write-Warning for local-over-global supplemental folder overrides."
}

if ($launcher -notmatch ':\$\(\$mount\.Mode\)') {
    throw "Expected PowerShell launcher to append the configured read-only/read-write mode to supplemental mounts."
}

if ($helper -notmatch 'Split-SupplementalFolderLine') {
    throw "Expected PowerShell helper to parse dependency-free supplemental folder config lines."
}

if ($helper -notmatch '\.ai-sandbox') {
    throw "Expected PowerShell helper to write local or global .ai-sandbox supplemental folder config."
}

if ($helper -notmatch 'supplemental-folders\.config') {
    throw "Expected PowerShell helper to write supplemental folder mappings to supplemental-folders.config."
}

if ($helper -notmatch '--read-write' -or $helper -notmatch '--read-only') {
    throw "Expected PowerShell helper to support scripted read-only/read-write flags."
}

if ($helper -notmatch 'LastIndexOf\(''\|''\)') {
    throw "Expected PowerShell helper to split supplemental config fields on the final pipe."
}

if ($helper -notmatch 'Replace') {
    throw "Expected PowerShell helper to prompt before replacing same-scope duplicate targets."
}

Write-Host "supplemental-folders.ps1 passed"
