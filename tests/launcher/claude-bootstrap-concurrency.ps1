[CmdletBinding()]
param(
    [string]$InitStatePath = "/repo/docker/bootstrap/init-state.sh",
    [string]$Engine = $(if ($env:AI_SANDBOX_ENGINE) { $env:AI_SANDBOX_ENGINE } else { 'auto' })
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../lib/runtime-engine.ps1")

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$suffix = "$script:EngineCommand-$([guid]::NewGuid().ToString('N'))"
$containerName = "ai-sandbox-claude-bootstrap-$suffix"
$originalError = $null
$cleanupError = $null

try {
    $output = Invoke-TestEngine run --name $containerName `
        -v "${repoRoot}:/repo:ro" `
        --entrypoint bash `
        ai-sandbox:latest /repo/tests/launcher/claude-bootstrap-concurrency.sh $InitStatePath 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "Concurrent Claude bootstrap failed:`n$($output -join "`n")"
    }

    Write-Host "claude-bootstrap-concurrency.ps1 passed"
} catch {
    $originalError = $_
} finally {
    try {
        if (Test-TestContainerExists $containerName) {
            Invoke-TestEngine rm -f $containerName | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "$script:EngineCommand rm exited $LASTEXITCODE"
            }
        }
    } catch {
        $cleanupError = $_
    }
}

if ($originalError) {
    if ($cleanupError) {
        throw "$($originalError.Exception.Message)`nCleanup error: $($cleanupError.Exception.Message)"
    }
    throw $originalError
}

if ($cleanupError) {
    throw $cleanupError
}
