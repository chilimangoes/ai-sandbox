[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bashLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox") -Raw
$psLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox.ps1") -Raw

foreach ($launcher in @($bashLauncher, $psLauncher)) {
    if ($launcher -match 'Get-FreePort|free_port|attemptT3Port|attempt_t3_host_port|port is already allocated|ports are not available|Get-ExistingHostAddress|existing_host_address') {
        throw "Expected launchers to use fixed workspace-address service ports without incremental port conflict retry or host-address migration checks."
    }
}

Write-Host "port-conflict-retry.ps1 passed"
