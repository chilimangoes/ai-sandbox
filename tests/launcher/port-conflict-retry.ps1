[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bashLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox") -Raw
$psLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox.ps1") -Raw

if ($bashLauncher -match 'Get-FreePort|free_port|attempt_t3_host_port|port is already allocated|ports are not available|existing_host_address') {
    throw 'Expected Bash Docker networking to retain fixed workspace-address ports.'
}
foreach ($expected in @(
    'if \(\$script:EngineCommand -eq ''podman''\) \{ 32 \} else \{ 1 \}',
    'Test-PortBlockAvailable -Endpoints \$endpoints',
    'No available Podman localhost port block after 32 attempts in 20000-49999\.',
    '\$hostPort = \$services\[\$index\]\.Port'
)) {
    if ($psLauncher -notmatch $expected) { throw "Expected bounded Podman allocation and fixed Docker ports: $expected" }
}

Write-Host "port-conflict-retry.ps1 passed"
