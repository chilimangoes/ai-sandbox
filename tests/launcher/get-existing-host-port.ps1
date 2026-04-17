[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $repoRoot "bin\ai-sandbox.ps1"
$scriptText = Get-Content $scriptPath -Raw
$bashLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox") -Raw
$defaultPortMatch = [regex]::Match($scriptText, '\$DefaultT3ContainerPort = (\d+)')
$defaultCodeNomadPortMatch = [regex]::Match($scriptText, '\$DefaultCodeNomadContainerPort = (\d+)')
$functionMatch = [regex]::Match(
    $scriptText,
    'function Get-ExistingHostPort \{.*?^\}',
    [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
    [System.Text.RegularExpressions.RegexOptions]::Multiline
)

if (-not $defaultPortMatch.Success) {
    throw "Could not locate DefaultT3ContainerPort in $scriptPath"
}

if (-not $defaultCodeNomadPortMatch.Success) {
    throw "Could not locate DefaultCodeNomadContainerPort in $scriptPath"
}

if (-not $functionMatch.Success) {
    throw "Could not locate Get-ExistingHostPort in $scriptPath"
}

if ($bashLauncher -notmatch 'DEFAULT_T3_CONTAINER_PORT=3773') {
    throw "Expected bin/ai-sandbox to define DEFAULT_T3_CONTAINER_PORT."
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-sandbox-test-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
    $dockerShim = Join-Path $tempDir "docker.cmd"
    $originalPath = $env:Path

    $setup = @"
`$DefaultT3ContainerPort = $($defaultPortMatch.Groups[1].Value)
`$DefaultCodeNomadContainerPort = $($defaultCodeNomadPortMatch.Groups[1].Value)
$($functionMatch.Value)
"@

    Set-Content -LiteralPath $dockerShim -Encoding ASCII -Value @'
@echo off
if "%1"=="port" (
  >&2 echo no public port '3773/tcp' published for %2
  exit /b 1
)
echo unexpected docker invocation %*
exit /b 99
'@

    $env:Path = "$tempDir;$originalPath"
    try {
        Invoke-Expression $setup
        $missing = Get-ExistingHostPort -Name "ai-sandbox-test" -ContainerPort $DefaultT3ContainerPort
    } finally {
        $env:Path = $originalPath
    }

    if ($null -ne $missing) {
        throw "Expected Get-ExistingHostPort to return `$null when Docker reports no published port, got: $missing"
    }

    Set-Content -LiteralPath $dockerShim -Encoding ASCII -Value @'
@echo off
if "%1"=="port" (
  if "%3"=="3773/tcp" (
    echo 0.0.0.0:3773
    echo [::]:3773
    exit /b 0
  )
  if "%3"=="9899/tcp" (
    echo 0.0.0.0:9899
    echo [::]:9899
    exit /b 0
  )
  exit /b 0
)
echo unexpected docker invocation %*
exit /b 99
'@

    $env:Path = "$tempDir;$originalPath"
    try {
        $resolved = Get-ExistingHostPort -Name "ai-sandbox-test" -ContainerPort $DefaultT3ContainerPort
        $resolvedCodeNomad = Get-ExistingHostPort -Name "ai-sandbox-test" -ContainerPort $DefaultCodeNomadContainerPort
    } finally {
        $env:Path = $originalPath
    }

    if ($resolved -ne 3773) {
        throw "Expected Get-ExistingHostPort to return 3773, got: $resolved"
    }

    if ($resolvedCodeNomad -ne 9899) {
        throw "Expected Get-ExistingHostPort to return 9899, got: $resolvedCodeNomad"
    }

    Write-Host "get-existing-host-port.ps1 passed"
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
