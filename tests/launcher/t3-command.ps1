[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
& python (Join-Path $PSScriptRoot "t3-dispatch.py")
if ($LASTEXITCODE -ne 0) { throw "T3 dispatch checks failed (exit $LASTEXITCODE)." }
Write-Host "t3-command.ps1 passed"
