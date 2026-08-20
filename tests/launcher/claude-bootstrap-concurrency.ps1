[CmdletBinding()]
param(
    [string]$InitStatePath = "/repo/docker/bootstrap/init-state.sh"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$suffix = [guid]::NewGuid().ToString("N")
$containerName = "ai-sandbox-claude-bootstrap-$suffix"
$originalError = $null
$cleanupError = $null

try {
    $output = & docker run --name $containerName `
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
        $existing = & docker ps -a --filter "name=^/${containerName}$" --format "{{.Names}}" 2>$null
        if ($existing -eq $containerName) {
            & docker rm -f $containerName | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "docker rm exited $LASTEXITCODE"
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
