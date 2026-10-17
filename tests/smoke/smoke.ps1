[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Engine = $(if ($env:AI_SANDBOX_ENGINE) { $env:AI_SANDBOX_ENGINE } else { 'auto' }),
    [switch]$SkipBuild,
    [switch]$NoCache,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgsList
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$ImageTag = "ai-sandbox:latest"
$ContainerName = "ai-sandbox-smoke-$([guid]::NewGuid().ToString('N'))"
. (Join-Path $RepoRoot 'scripts/lib/engine.ps1')
$options = Get-SandboxOptions -Engine $Engine -Arguments $ArgsList -AllowNoCache -AllowSkipBuild
$script:EngineCommand = Resolve-SandboxEngine $options.Engine
$ContainerName = "$ContainerName-$script:EngineCommand"

if (-not ($SkipBuild -or $options.SkipBuild)) {
    & (Join-Path $RepoRoot 'scripts/build-image.ps1') -Engine $script:EngineCommand -NoCache:($NoCache -or $options.NoCache)
}
try {
    Invoke-SandboxEngine run --rm --name $ContainerName $ImageTag /opt/ai-sandbox/image-smoke-check.sh
    if ($LASTEXITCODE -ne 0) { throw "$script:EngineCommand smoke check failed (exit $LASTEXITCODE)." }
} finally {
    # Exact unique names and the resolved CLI keep cleanup in this test's store.
    $existing = Invoke-SandboxEngine ps -a --format '{{.Names}}'
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect smoke cleanup.' }
    if (@($existing | ForEach-Object { $_.TrimStart('/') }) -contains $ContainerName) {
        Invoke-SandboxEngine rm -f $ContainerName | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not remove smoke container.' }
    }
}
