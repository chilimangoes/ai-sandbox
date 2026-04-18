[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$initState = Get-Content (Join-Path $repoRoot "docker\bootstrap\init-state.sh") -Raw

if ($initState -notmatch 'state/config/paseo/config\.json') {
    throw "Expected init-state.sh to handle the persisted Paseo config file."
}

if ($initState -notmatch '\$schema') {
    throw "Expected init-state.sh to normalize legacy Paseo configs that still include `$schema."
}

Write-Host "paseo-config-migration.ps1 passed"
