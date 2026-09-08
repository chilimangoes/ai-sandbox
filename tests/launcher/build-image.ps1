[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source = Get-Content (Join-Path $repoRoot "bin/ai-sandbox.ps1") -Raw
$match = [regex]::Match($source, '(?ms)^function Build-Image \{.*?^\}')
if (-not $match.Success) { throw "Build-Image function missing" }
Invoke-Expression $match.Value

$ImageTag = "test:latest"
$RepoRoot = "C:\workspace with spaces"
$script:dockerExitCode = 0
function docker {
    $script:dockerArgs = @($args)
    $global:LASTEXITCODE = $script:dockerExitCode
}

Build-Image -Pull
if ($script:dockerArgs -contains "--no-cache") { throw "Initial build should allow caching" }
Build-Image -Pull -Refresh
foreach ($expected in @("--pull", "--no-cache", $ImageTag, $RepoRoot)) {
    if ($script:dockerArgs -notcontains $expected) { throw "Missing build argument: $expected" }
}
if ($source -notmatch 'Build-Image -Pull -Refresh:\(\$update -or \$rebuild\)') {
    throw "Both explicit update modes must request fresh packages"
}

$script:dockerExitCode = 17
$failed = $false
try { Build-Image -Pull -Refresh } catch {
    if ($_.Exception.Message -notmatch 'build failed') { throw }
    $failed = $true
}
if (-not $failed) { throw "Failed builds must stop before replacing the container" }
Write-Host "build-image.ps1 passed"
