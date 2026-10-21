[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

& docker run --rm --network none --mount "type=bind,source=$repoRoot,target=/repo,readonly" `
    --entrypoint python3 ai-sandbox:latest /repo/tests/launcher/t3-startup-recovery.py
if ($LASTEXITCODE -ne 0) { throw "T3 recovery checks failed (exit $LASTEXITCODE)." }

& docker run --rm --mount "type=bind,source=$repoRoot,target=/repo,readonly" `
    -e LOCAL_UID=12345 -e LOCAL_GID=12345 --entrypoint bash ai-sandbox:latest -c `
    'cp /repo/docker/entrypoint.sh /opt/ai-sandbox/entrypoint.sh && cp /repo/docker/t3-startup.py /opt/ai-sandbox/t3-startup.py && exec /opt/ai-sandbox/entrypoint.sh python3 /repo/tests/launcher/t3-startup-runtime.py'
if ($LASTEXITCODE -ne 0) { throw "T3 recovery runtime checks failed (exit $LASTEXITCODE)." }

Write-Host "t3-startup-recovery.ps1 passed"
