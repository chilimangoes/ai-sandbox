[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Engine = $(if ($env:AI_SANDBOX_ENGINE) { $env:AI_SANDBOX_ENGINE } else { 'auto' }),
    [switch]$NoCache,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgsList
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $PSScriptRoot 'lib/engine.ps1')
$options = Get-SandboxOptions -Engine $Engine -Arguments $ArgsList -AllowNoCache
$script:EngineCommand = Resolve-SandboxEngine $options.Engine
$buildArgs = @('build', $(if ($script:EngineCommand -eq 'podman') { '--pull=always' } else { '--pull' }), '-t', 'ai-sandbox:latest')
if ($NoCache -or $options.NoCache) { $buildArgs += '--no-cache' }
Invoke-SandboxEngine @buildArgs $RepoRoot
if ($LASTEXITCODE -ne 0) { throw "$script:EngineCommand build failed (exit $LASTEXITCODE)." }
