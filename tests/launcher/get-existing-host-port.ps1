[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $repoRoot "bin\ai-sandbox.ps1"
$scriptText = Get-Content $scriptPath -Raw
$defaultPortMatch = [regex]::Match($scriptText, '\$DefaultContainerPort = (\d+)')
$functionMatch = [regex]::Match(
    $scriptText,
    'function Get-ExistingHostPort \{.*?^\}',
    [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
    [System.Text.RegularExpressions.RegexOptions]::Multiline
)

if (-not $defaultPortMatch.Success) {
    throw "Could not locate DefaultContainerPort in $scriptPath"
}

if (-not $functionMatch.Success) {
    throw "Could not locate Get-ExistingHostPort in $scriptPath"
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-sandbox-test-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
    $dockerShim = Join-Path $tempDir "docker.cmd"
    $originalPath = $env:Path

    $setup = @"
`$DefaultContainerPort = $($defaultPortMatch.Groups[1].Value)
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
        $missing = Get-ExistingHostPort -Name "ai-sandbox-test"
    } finally {
        $env:Path = $originalPath
    }

    if ($null -ne $missing) {
        throw "Expected Get-ExistingHostPort to return `$null when Docker reports no published port, got: $missing"
    }

    Set-Content -LiteralPath $dockerShim -Encoding ASCII -Value @'
@echo off
if "%1"=="port" (
  echo 0.0.0.0:3773
  echo [::]:3773
  exit /b 0
)
echo unexpected docker invocation %*
exit /b 99
'@

    $env:Path = "$tempDir;$originalPath"
    try {
        $resolved = Get-ExistingHostPort -Name "ai-sandbox-test"
    } finally {
        $env:Path = $originalPath
    }

    if ($resolved -ne 3773) {
        throw "Expected Get-ExistingHostPort to return 3773, got: $resolved"
    }

    Write-Host "get-existing-host-port.ps1 passed"
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
