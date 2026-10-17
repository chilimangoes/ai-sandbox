[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts/lib/engine.ps1')
$global:ToolCalls = New-Object System.Collections.Generic.List[object]
$global:ToolHealth = @{ docker = $true; podman = $true }
$global:ToolExit = 0
$global:ToolPodmanLocal = $false
$global:ToolInfoReady = $true
$global:ToolNames = @{ docker = @('foreign-docker'); podman = @('foreign-podman') }
function Invoke-ToolStub {
    param([string]$Name, [object[]]$Arguments)
    $global:ToolCalls.Add(@($Name) + $Arguments)
    $global:LASTEXITCODE = 0
    if ($Arguments[0] -eq '--version') { return "$Name version client-test" }
    if ($Arguments[0] -eq 'info') {
        if (-not $global:ToolInfoReady) { $global:LASTEXITCODE = 17; return }
        if ($global:ToolPodmanLocal) { return '{"Host":{"serviceIsRemote":false}}' }
        return '{"Host":{"serviceIsRemote":true}}'
    }
    if ($Arguments[0] -eq 'version') {
        if (-not $global:ToolHealth[$Name]) { $global:LASTEXITCODE = 17; return }
        if ($Name -eq 'podman' -and $global:ToolPodmanLocal) { return '{"Client":{"Version":"client-test"}}' }
        return '{"Client":{"Version":"client-test"},"Server":{"Version":"server-test"}}'
    }
    if ($Arguments[0] -eq 'ps') { return $global:ToolNames[$Name] }
    if ($Arguments[0] -eq 'run') {
        $index = [array]::IndexOf($Arguments, '--name')
        if ($index -ge 0) { $global:ToolNames[$Name] += @($Arguments[$index + 1], "$($Arguments[$index + 1])-other") }
    }
    if ($Arguments[0] -eq 'rm') {
        if ($Arguments[-1] -match '^foreign-|\-other$') { throw 'Cleanup crossed fixture boundaries.' }
        $global:ToolNames[$Name] = @($global:ToolNames[$Name] | Where-Object { $_ -ne $Arguments[-1] })
        return
    }
    $global:LASTEXITCODE = $global:ToolExit
}
function docker { Invoke-ToolStub docker $args }
function podman { Invoke-ToolStub podman $args }
function Assert-Fails {
    param([scriptblock]$Action, [string]$Expected)
    try { & $Action; throw 'Expected failure was absent.' } catch {
        if ($_.Exception.Message -notmatch $Expected) { throw }
    }
}
$previousEngine = $env:AI_SANDBOX_ENGINE
try {
    if ((Resolve-SandboxEngine auto) -ne 'docker') { throw 'Auto must prefer Docker.' }
    $global:ToolHealth.docker = $false
    if ((Resolve-SandboxEngine auto) -ne 'podman') { throw 'Auto must fall back to healthy Podman.' }
    Assert-Fails { Resolve-SandboxEngine docker } 'unreachable'
    Assert-Fails { Resolve-SandboxEngine invalid } 'Invalid engine'
    Assert-Fails { Resolve-SandboxEngine PODMAN } 'Invalid engine'
    # Both launchers use this same preference and explicit failure policy.
    $launcherSource = Get-Content (Join-Path $repoRoot 'bin/ai-sandbox.ps1') -Raw
    foreach ($name in @('Test-EngineHealthy', 'Resolve-Engine')) {
        Invoke-Expression ([regex]::Match($launcherSource, "(?ms)^function $name \{.*?^\}").Value)
    }
    if ((Resolve-Engine auto) -ne (Resolve-SandboxEngine auto)) { throw 'Helper auto policy differs from launcher.' }
    Assert-Fails { Resolve-Engine docker } 'unavailable or unhealthy'
    $missing = Get-SandboxEngineStatus ai_sandbox_no_such_engine
    if ($missing.Client -ne 'missing' -or $missing.Ready) { throw 'Missing client must be distinct.' }
    $global:ToolHealth.docker = $true
    $global:ToolPodmanLocal = $true
    $local = Get-SandboxEngineStatus podman
    if (-not $local.Ready -or $local.Server -notmatch 'not applicable.*local Podman') { throw 'Local daemonless Podman must be healthy.' }
    $global:ToolInfoReady = $false
    if ((Get-SandboxEngineStatus podman).Ready) { throw 'Broken local Podman storage/runtime must fail.' }
    $global:ToolInfoReady = $true
    $global:ToolPodmanLocal = $false
    $Engine = 'docker'
    . (Join-Path $repoRoot 'tests/lib/runtime-engine.ps1')
    $global:ToolCalls.Clear()
    Invoke-TestEngine run --rm -v 'C:\workspace with spaces:/repo:ro' ai-sandbox:latest bash -c 'printf literal'
    $runtimeRun = @($global:ToolCalls | Where-Object { $_[1] -eq 'run' })[0]
    if ($runtimeRun -notcontains '-v' -or $runtimeRun -notcontains 'C:\workspace with spaces:/repo:ro') { throw 'Runtime adapter consumed a native argument as a PowerShell parameter.' }
    foreach ($selected in @('docker', 'podman')) {
        $env:AI_SANDBOX_ENGINE = $selected
        $global:ToolCalls.Clear()
        & (Join-Path $repoRoot 'scripts/build-image.ps1')
        $build = @($global:ToolCalls | Where-Object { $_[1] -eq 'build' })[0]
        $pull = if ($selected -eq 'podman') { '--pull=always' } else { '--pull' }
        if ($build[0] -ne $selected -or $build -notcontains $pull -or $build -contains '--no-cache') { throw 'Initial build policy differs.' }
        $global:ToolCalls.Clear()
        $other = if ($selected -eq 'docker') { 'podman' } else { 'docker' }
        & (Join-Path $repoRoot 'scripts/build-image.ps1') --engine $other --no-cache
        $build = @($global:ToolCalls | Where-Object { $_[1] -eq 'build' })[0]
        if ($build[0] -ne $other -or $build -notcontains '--no-cache' -or $build[-1] -ne $repoRoot) { throw 'CLI precedence/no-cache/context failed.' }
        $global:ToolCalls.Clear()
        & (Join-Path $repoRoot 'tests/smoke/smoke.ps1') -Engine $selected -SkipBuild
        & (Join-Path $repoRoot 'tests/smoke/smoke.ps1') --engine $selected --skip-build
        $runs = @($global:ToolCalls | Where-Object { $_[1] -eq 'run' })
        if ($runs.Count -ne 2 -or $runs[0][4] -eq $runs[1][4]) { throw 'Smoke fixtures must be unique.' }
        foreach ($run in $runs) {
            if ($run[0] -ne $selected -or $run -notcontains '/opt/ai-sandbox/image-smoke-check.sh') { throw 'Smoke dispatched to wrong engine/check.' }
        }
        & (Join-Path $repoRoot 'scripts/doctor.ps1') --engine $selected
    }
    $global:ToolExit = 23
    $Engine = 'docker'
    . (Join-Path $repoRoot 'tests/lib/runtime-engine.ps1')
    Invoke-TestEngine run --name owned-failed-run ai-sandbox:latest false
    if ($LASTEXITCODE -ne 23 -or $global:ToolNames.docker -contains 'owned-failed-run') { throw 'Failed run cleanup lost the native failure or leaked its container.' }
    Assert-Fails { & (Join-Path $repoRoot 'scripts/build-image.ps1') -Engine podman } 'build failed'
    Assert-Fails { & (Join-Path $repoRoot 'tests/smoke/smoke.ps1') -Engine podman -SkipBuild } 'smoke check failed'
    $global:ToolHealth.podman = $false
    Assert-Fails { & (Join-Path $repoRoot 'scripts/doctor.ps1') -Engine podman } 'podman machine start'
    Assert-Fails { & (Join-Path $repoRoot 'scripts/build-image.ps1') --engine } 'Missing engine'
    $savedDocker = ${function:docker}
    $savedPath = $env:PATH
    try {
        Remove-Item function:docker
        $env:PATH = ''
        Assert-Fails { & (Join-Path $repoRoot 'scripts/doctor.ps1') -Engine docker } 'client is missing'
    } finally {
        $env:PATH = $savedPath
        Set-Item function:docker $savedDocker
    }
    if ((Get-Content (Join-Path $repoRoot 'Dockerfile') -TotalCount 1) -ne 'FROM docker.io/library/debian:bookworm-slim') { throw 'Base image must be qualified.' }
    Write-Host 'operational-tools.ps1 passed'
} finally {
    $env:AI_SANDBOX_ENGINE = $previousEngine
    Remove-Variable ToolCalls, ToolHealth, ToolExit, ToolPodmanLocal, ToolInfoReady, ToolNames -Scope Global
}
