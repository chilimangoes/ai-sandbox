[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
& python (Join-Path $PSScriptRoot "t3-output.py")
if ($LASTEXITCODE -ne 0) { throw "T3 output checks failed (exit $LASTEXITCODE)." }
Write-Host "t3-output.ps1 passed"
