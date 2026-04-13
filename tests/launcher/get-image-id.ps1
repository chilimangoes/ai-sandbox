[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $repoRoot "bin\ai-sandbox.ps1"
$scriptText = Get-Content $scriptPath -Raw
$match = [regex]::Match(
    $scriptText,
    'function Get-ImageId \{.*?^\}',
    [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
    [System.Text.RegularExpressions.RegexOptions]::Multiline
)

if (-not $match.Success) {
    throw "Could not locate Get-ImageId in $scriptPath"
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-sandbox-test-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
    $dockerShim = Join-Path $tempDir "docker.cmd"
    Set-Content -LiteralPath $dockerShim -Encoding ASCII -Value @'
@echo off
if "%1"=="image" if "%2"=="inspect" (
  >&2 echo Error response from daemon: No such image: %4
  exit /b 1
)
echo unexpected docker invocation %*
exit /b 99
'@

    $originalPath = $env:Path
    $originalPref = $global:PSNativeCommandUseErrorActionPreference
    $env:Path = "$tempDir;$originalPath"

    try {
        Invoke-Expression $match.Value
        $result = Get-ImageId -Tag "ai-sandbox:latest"
    } finally {
        $env:Path = $originalPath
        $global:PSNativeCommandUseErrorActionPreference = $originalPref
    }

    if ($null -ne $result) {
        throw "Expected Get-ImageId to return `$null for a missing image, got: $result"
    }

    Set-Content -LiteralPath $dockerShim -Encoding ASCII -Value @'
@echo off
if "%1"=="image" if "%2"=="inspect" (
  echo sha256:test-image-id
  exit /b 0
)
echo unexpected docker invocation %*
exit /b 99
'@

    $env:Path = "$tempDir;$originalPath"
    try {
        $resolved = Get-ImageId -Tag "ai-sandbox:latest"
    } finally {
        $env:Path = $originalPath
    }

    if ($resolved -ne "sha256:test-image-id") {
        throw "Expected Get-ImageId to return the image id, got: $resolved"
    }

    Write-Host "get-image-id.ps1 passed"
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
