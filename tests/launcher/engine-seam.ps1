[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source = Get-Content (Join-Path $repoRoot "bin/ai-sandbox.ps1") -Raw
$bashSource = Get-Content (Join-Path $repoRoot "bin/ai-sandbox") -Raw
if ($source -match '& docker|ProcessStartInfo') { throw "Engine operations must use the selected adapter" }
$psUsage = [regex]::Match($source, '(?m)^Usage:.*$').Value.Trim()
$bashUsage = [regex]::Match($bashSource, '(?m)^  echo "(Usage:.*)"$').Groups[1].Value
if ($psUsage -cne $bashUsage) { throw "Launcher help must match" }

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("ai-sandbox-engine-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$originalPath = $env:Path
$originalEngine = $env:AI_SANDBOX_ENGINE
$originalNativePreference = $PSNativeCommandUseErrorActionPreference
try {
    $shim = @'
@echo off
if "%1"=="version" goto health
if "%1"=="%AI_TEST_FAIL_OPERATION%" goto failed
if "%1 %2"=="%AI_TEST_FAIL_OPERATION%" goto failed
if "%AI_TEST_MISSING%"=="1" goto missing
if "%1"=="ps" (echo %AI_TEST_NAMES%& exit /b 0)
if "%1 %2"=="image ls" exit /b 0
if "%1"=="image" (echo [{"Id":"%AI_TEST_IMAGE%"}]& exit /b 0)
if "%1"=="inspect" (
  echo [{"Name":"workspace","Image":"%AI_TEST_IMAGE%","State":{"Running":true},"Config":{"Labels":%AI_TEST_LABELS%}}]
  exit /b 0
)
if "%1"=="port" (echo %AI_TEST_ENDPOINT%& exit /b 0)
if "%1"=="volume" (
  if "%2"=="ls" if not "%AI_TEST_VOLUME_NAMES%"=="" (echo %AI_TEST_VOLUME_NAMES%& exit /b 0)
  if "%2"=="ls" (echo %AI_TEST_NAMES%& exit /b 0)
  if "%2"=="create" (echo %3>>"%AI_TEST_VOLUME_LOG%"& exit /b 0)
  if "%2"=="inspect" (echo [{"Name":"%3"}]& exit /b 0)
  if "%2"=="rm" exit /b 0
)
if "%1"=="exec" goto exec
if "%1"=="stop" exit /b 0
if "%1"=="rm" exit /b 0
>&2 echo unexpected invocation
exit /b 99
:health
if "%~n0"=="docker" if not "%AI_TEST_DOCKER_HEALTH%"=="1" exit /b 1
if "%~n0"=="podman" if not "%AI_TEST_PODMAN_HEALTH%"=="1" exit /b 1
>&2 echo harmless native diagnostic
exit /b 0
:missing
if "%1"=="ps" exit /b 0
if "%1 %2"=="image ls" exit /b 0
>&2 echo resource not found
exit /b 1
:failed
>&2 echo deliberate engine failure
exit /b 23
:exec
if "%AI_TEST_EXEC_LOG%"=="" exit /b 0
>>"%AI_TEST_EXEC_LOG%" echo %~n0
:exec_argument
if "%~1"=="" exit /b 0
>>"%AI_TEST_EXEC_LOG%" echo %~1
shift
goto exec_argument
'@
    foreach ($engine in @("docker", "podman")) {
        Set-Content (Join-Path $tempDir "$engine.cmd") -Encoding ASCII -Value $shim
    }
    $env:Path = "$tempDir;$originalPath"
    $selectionScript = Join-Path $tempDir "selection.ps1"
    $selectionEnd = [regex]::Match($source, '(?m)^\$script:EngineCommand = Resolve-Engine.*$')
    if (-not $selectionEnd.Success) { throw "Engine resolution missing" }
    Set-Content $selectionScript -Value ($source.Substring(0, $selectionEnd.Index + $selectionEnd.Length) + "`nWrite-Output `$script:EngineCommand")

    function Assert-Selection {
        param([string]$Environment, [string[]]$Arguments, [string]$Expected, [switch]$Fails, [string]$FailureMessage)
        $env:AI_SANDBOX_ENGINE = $Environment
        $ErrorActionPreference = "Continue"
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selectionScript @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($Fails) {
            if ($exitCode -eq 0) { throw "Selection should have failed: $Arguments" }
            if ($FailureMessage -and ($output -join "`n") -notlike "*$FailureMessage*") { throw "Missing safe machine guidance: $output" }
        } elseif ($exitCode -ne 0 -or ($output -join "`n").Trim() -cne $Expected) {
            throw "Expected $Expected for env=$Environment args=$Arguments health=$env:AI_TEST_DOCKER_HEALTH/$env:AI_TEST_PODMAN_HEALTH, got exit $exitCode and $output"
        }
    }
    $env:AI_TEST_DOCKER_HEALTH = "1"
    $env:AI_TEST_PODMAN_HEALTH = "1"
    Assert-Selection -Expected docker
    Assert-Selection -Environment podman -Expected podman
    Assert-Selection -Environment invalid -Arguments @("--engine", "docker") -Expected docker
    Assert-Selection -Environment podman -Arguments @("--engine", "auto") -Expected docker
    foreach ($invalid in @("invalid", "Docker", "")) {
        Assert-Selection -Arguments @("--engine", $invalid) -Fails
    }
    Assert-Selection -Environment invalid -Fails
    Assert-Selection -Arguments @("--engine") -Fails
    Assert-Selection -Environment invalid -Arguments @("--help") -Expected $psUsage
    $env:AI_TEST_DOCKER_HEALTH = "0"
    Assert-Selection -Expected podman
    Assert-Selection -Arguments @("--engine", "docker") -Fails
    $env:AI_TEST_PODMAN_HEALTH = "0"
    Assert-Selection -Fails
    $env:AI_TEST_DOCKER_HEALTH = "1"
    Assert-Selection -Arguments @("--engine", "podman") -Fails -FailureMessage 'podman machine start <name>'
    Rename-Item (Join-Path $tempDir "podman.cmd") "podman-disabled.cmd"
    # Hide installed engines as well when checking command absence.
    $env:Path = "$tempDir;$env:SystemRoot\System32;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
    Assert-Selection -Arguments @("--engine", "podman") -Fails
    Rename-Item (Join-Path $tempDir "podman-disabled.cmd") "podman.cmd"
    $env:Path = "$tempDir;$originalPath"

    foreach ($name in @("Invoke-Engine", "Invoke-EngineQuery", "Test-ContainerExists", "Test-ContainerRunning", "Get-ContainerInspection", "Get-ImageId", "Get-ContainerImageId", "Get-ContainerSupplementalFolderSignature", "Get-ExistingHostPort", "Ensure-Volume")) {
        $match = [regex]::Match($source, "(?ms)^function $name \{.*?^\}")
        if (-not $match.Success) { throw "Missing helper $name" }
        Invoke-Expression $match.Value
    }
    $PSNativeCommandUseErrorActionPreference = $true
    $env:AI_TEST_VOLUME_LOG = Join-Path $tempDir "volumes.log"
    foreach ($engine in @("docker", "podman")) {
        $script:EngineCommand = $engine
        $env:AI_TEST_MISSING = "0"
        $env:AI_TEST_NAMES = if ($engine -eq "docker") { "/workspace" } else { "workspace" }
        if (-not (Test-ContainerExists workspace) -or -not (Test-ContainerRunning workspace)) { throw "Name normalization failed" }
        foreach ($other in @("work", "Workspace", "workspace-other")) {
            if (Test-ContainerExists $other) { throw "Matched a different container: $other" }
        }
        $env:AI_TEST_LABELS = '{}'
        foreach ($image in @('abcdef', 'sha256:abcdef')) {
            $env:AI_TEST_IMAGE = $image
            if ((Get-ImageId test) -cne "abcdef" -or (Get-ContainerImageId workspace) -cne "abcdef") { throw "Image normalization failed for $engine $image" }
        }
        $env:AI_TEST_NAMES = 'workspace-prefix-decoy'
        if ((Test-ContainerExists workspace) -or (Test-ContainerRunning workspace)) { throw 'A prefix-only match selected a container.' }
        $env:AI_TEST_NAMES = 'workspace'
        $env:AI_TEST_LABELS = '{"unrelated":"value", "ai-sandbox.supplemental-folders": "abcdef"}'
        if ((Get-ContainerSupplementalFolderSignature workspace) -cne "abcdef") { throw "Label parsing failed" }
        foreach ($labels in @("null", "{}", '{"ai-sandbox.supplemental-folders":null}')) {
            $env:AI_TEST_LABELS = $labels
            if ($null -ne (Get-ContainerSupplementalFolderSignature workspace)) { throw "Missing or malformed label should be null" }
        }
        foreach ($endpoint in @("127.64.1.2:3773", "0.0.0.0:3773", "[::]:3773", "[::1]:3773")) {
            $env:AI_TEST_ENDPOINT = $endpoint
            if ((Get-ExistingHostPort workspace 3773) -ne 3773) { throw "Endpoint parsing failed: $endpoint" }
        }
        $env:AI_TEST_ENDPOINT = "unpublished"
        if ($null -ne (Get-ExistingHostPort workspace 3773)) { throw "Invalid endpoint should be null" }
        $env:AI_TEST_NAMES = "state"
        Ensure-Volume state
        Ensure-Volume State
        $env:AI_TEST_NAMES = 'state-prefix-decoy'
        Ensure-Volume state
        $env:AI_TEST_MISSING = "1"
        if (Test-ContainerExists workspace) { throw "Missing container should not exist" }
        foreach ($value in @((Get-ImageId missing), (Get-ContainerImageId missing), (Get-ContainerSupplementalFolderSignature missing), (Get-ExistingHostPort missing 3773))) {
            if ($null -ne $value) { throw "Missing resource should return null" }
        }
    }
    if (@(Get-Content $env:AI_TEST_VOLUME_LOG).Count -ne 4) { throw "Volume names must match case and the full name exactly" }

    # Execute the actual top-level dispatch with fixture metadata, avoiding live
    # resources while checking that native exec and mutation failures escape.
    $dispatchScript = Join-Path $tempDir "dispatch.ps1"
    $fixtures = @'
function Get-WorkspaceMeta {
    [pscustomobject]@{ Container = "workspace"; Workspace = "fixture"; Hash = "000000000000"; HostAddress = "127.0.0.1"; ContainerWorkspacePath = "/workspace"; ConfigVolume = "state"; AuthVolume = "state"; DataVolume = "state"; CacheVolume = "state" }
}
function Get-SupplementalFolderMounts { [pscustomobject]@{ Warnings = @() } }
function Ensure-Container { param($Meta) $Meta | Add-Member Endpoints @(Get-CandidateEndpoints -Meta $Meta) }
'@
    $selectionOffset = $selectionEnd.Index + $selectionEnd.Length
    Set-Content $dispatchScript -Value ($source.Substring(0, $selectionOffset) + "`n" + $fixtures + "`n" + $source.Substring($selectionOffset))
    $env:AI_TEST_DOCKER_HEALTH = "1"
    $env:AI_TEST_PODMAN_HEALTH = "1"
    $env:AI_SANDBOX_ENGINE = $null
    $env:AI_TEST_MISSING = "0"
    $env:AI_TEST_NAMES = "workspace"
    $env:AI_TEST_IMAGE = "abcdef"
    $env:AI_TEST_VOLUME_NAMES = "state"
    foreach ($engine in @("docker", "podman")) {
        foreach ($command in @("reset-config", "doctor", "t3", "shell")) {
            $env:AI_TEST_FAIL_OPERATION = "exec"
            $ErrorActionPreference = "Continue"
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dispatchScript --engine $engine $command *> $null
            $ErrorActionPreference = "Stop"
            if ($LASTEXITCODE -ne 23) { throw "Exec exit code was lost for $engine $command" }
        }
        foreach ($case in @(@("stop", "stop"), @("rm", "rm"), @("reset-state", "rm"), @("reset-state", "volume rm"), @("rm", "ps"), @("reset-state", "volume ls"))) {
            $env:AI_TEST_FAIL_OPERATION = $case[1]
            $ErrorActionPreference = "Continue"
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dispatchScript --engine $engine $case[0] *> $null
            $ErrorActionPreference = "Stop"
            if ($LASTEXITCODE -eq 0) { throw "Mutation failure was hidden for $engine $case" }
        }
        $env:AI_TEST_FAIL_OPERATION = ""
        $env:AI_TEST_NAMES = "another-workspace"
        $env:AI_TEST_VOLUME_NAMES = "another-state"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dispatchScript --engine $engine reset-state *> $null
        if ($LASTEXITCODE -ne 0) { throw "Removing missing resources should succeed" }
        $env:AI_TEST_NAMES = "workspace"
        $env:AI_TEST_VOLUME_NAMES = "state"
    }
    $env:AI_TEST_EXEC_LOG = Join-Path $tempDir "exec.log"
    foreach ($engine in @("docker", "podman")) {
        Remove-Item -LiteralPath $env:AI_TEST_EXEC_LOG -ErrorAction SilentlyContinue
        $env:AI_SANDBOX_ENGINE = if ($engine -eq "docker") { "podman" } else { "docker" }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dispatchScript --engine $engine t3 --help --engine other-engine --unknown --update --rebuild "value with spaces" *> $null
        if ($LASTEXITCODE -ne 0) { throw "Tool argument dispatch failed" }
        $invocation = @(Get-Content -LiteralPath $env:AI_TEST_EXEC_LOG)
        if ($invocation[0] -cne $engine) { throw "A tool's --engine argument changed the selected launcher engine" }
        $expectedArguments = @("t3", "--help", "--engine", "other-engine", "--unknown", "--update", "--rebuild", "value with spaces")
        if (($invocation[($invocation.Count - $expectedArguments.Count)..($invocation.Count - 1)] -join "`n") -cne ($expectedArguments -join "`n")) {
            throw "Tool flags or spaced arguments changed before exec"
        }
    }
    Write-Host "engine-seam.ps1 passed (including Windows PowerShell 5.1 native stderr)"
} finally {
    $env:Path = $originalPath
    $env:AI_SANDBOX_ENGINE = $originalEngine
    $PSNativeCommandUseErrorActionPreference = $originalNativePreference
    Get-ChildItem Env:AI_TEST_* | Remove-Item
    if (([IO.Path]::GetFullPath($tempDir)).StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}
