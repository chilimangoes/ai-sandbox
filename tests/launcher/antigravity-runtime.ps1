[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$image = if ($env:AI_SANDBOX_TEST_IMAGE) { $env:AI_SANDBOX_TEST_IMAGE } else { "ai-sandbox:latest" }
$volume = "ai-sandbox-antigravity-test-$([guid]::NewGuid().ToString('N'))"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

docker volume create $volume | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not create Antigravity test volume." }
try {
    foreach ($phase in @("seed", "verify")) {
        docker run --rm -v "${volume}:/state" -v "${repoRoot}:/repo:ro" $image `
            python3 /repo/tests/launcher/antigravity-runtime.py $phase
        if ($LASTEXITCODE -ne 0) { throw "Antigravity runtime test failed in phase $phase." }
    }
} finally {
    docker volume rm $volume | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not remove Antigravity test volume." }
}
Write-Host "antigravity-runtime.ps1 passed"
