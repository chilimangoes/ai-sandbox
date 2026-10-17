[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Engine = $(if ($env:AI_SANDBOX_ENGINE) { $env:AI_SANDBOX_ENGINE } else { 'auto' }),
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgsList
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot 'lib/engine.ps1')
$options = Get-SandboxOptions -Engine $Engine -Arguments $ArgsList
$Engine = $options.Engine
try { $selected = Resolve-SandboxEngine $Engine } catch {
    foreach ($name in $(if ($Engine -ceq 'auto') { @('docker', 'podman') } else { @($Engine) })) {
        $status = Get-SandboxEngineStatus $name
        Write-Host "${name}: client=$($status.Client); server=$($status.Server); ready=false"
    }
    throw
}
$status = Get-SandboxEngineStatus $selected
Write-Host "engine: $selected"
Write-Host "client: $($status.Client)"
Write-Host "server: $($status.Server)"
Write-Host "ready: $($status.Ready.ToString().ToLowerInvariant())"
Write-Host ("pwsh: " + $PSVersionTable.PSVersion.ToString())
