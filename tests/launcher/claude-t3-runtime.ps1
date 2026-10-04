[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$containerName = "ai-sandbox-claude-t3-$([guid]::NewGuid().ToString('N'))"

try {
    & docker run --rm --name $containerName -v "${repoRoot}:/repo:ro" `
        --entrypoint bash ai-sandbox:latest -c `
        'cp /repo/docker/entrypoint.sh /opt/ai-sandbox/entrypoint.sh && cp /repo/docker/claude-wrapper.sh /opt/ai-sandbox/claude-wrapper.sh && exec /opt/ai-sandbox/entrypoint.sh python3 /repo/tests/launcher/claude-t3-runtime.py'
    if ($LASTEXITCODE -ne 0) {
        throw "Claude T3 runtime regression failed (exit $LASTEXITCODE)."
    }
    Write-Host "claude-t3-runtime.ps1 passed"
} finally {
    $existing = & docker ps -a --filter "name=^/${containerName}$" --format '{{.Names}}'
    if ($existing -eq $containerName) {
        & docker rm -f $containerName | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not remove test container $containerName." }
    }
}
