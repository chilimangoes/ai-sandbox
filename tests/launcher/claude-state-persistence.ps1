[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$suffix = [guid]::NewGuid().ToString("N")
$containerName = "ai-sandbox-claude-state-$suffix"
$volumes = @(
    "ai-sandbox-claude-config-$suffix",
    "ai-sandbox-claude-auth-$suffix",
    "ai-sandbox-claude-data-$suffix",
    "ai-sandbox-claude-cache-$suffix"
)
$createdVolumes = New-Object System.Collections.Generic.List[string]
$containerCreated = $false
$originalError = $null
$cleanupErrors = New-Object System.Collections.Generic.List[string]

function Invoke-Docker {
    param([string[]]$DockerArgs)
    $output = & docker @DockerArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
        throw "docker $($DockerArgs -join ' ') exited $LASTEXITCODE. $details"
    }
    return $output
}

function Start-TestContainer {
    Invoke-Docker @(
        "run", "-d", "--name", $containerName,
        "-v", "$($volumes[0]):/state/config",
        "-v", "$($volumes[1]):/state/auth",
        "-v", "$($volumes[2]):/state/data",
        "-v", "$($volumes[3]):/state/cache",
        "ai-sandbox:latest", "daemon"
    ) | Out-Null
    $script:containerCreated = $true
}

try {
    foreach ($volume in $volumes) {
        Invoke-Docker @("volume", "create", $volume) | Out-Null
        $createdVolumes.Add($volume)
    }

    Invoke-Docker @(
        "run", "--rm", "--entrypoint", "bash",
        "-v", "$($volumes[2]):/state/data",
        "ai-sandbox:latest", "-lc",
        "mkdir -p /home/sandbox/.claude && printf legacy-dir > /home/sandbox/.claude/legacy-marker && printf '{`"marker`":`"legacy-json`"}\n' > /home/sandbox/.claude.json && /opt/ai-sandbox/bootstrap/init-state.sh && grep -qx legacy-dir /state/data/claude/home/legacy-marker && grep -q legacy-json /state/data/claude/claude.json && test -L /home/sandbox/.claude"
    ) | Out-Null

    Invoke-Docker @(
        "run", "--rm", "--entrypoint", "bash",
        "-v", "$($volumes[2]):/state/data",
        "ai-sandbox:latest", "-lc",
        "mkdir -p /home/sandbox/.claude && printf should-not-win > /home/sandbox/.claude/legacy-marker && printf '{`"marker`":`"should-not-win`"}\n' > /home/sandbox/.claude.json && /opt/ai-sandbox/bootstrap/init-state.sh && grep -qx legacy-dir /state/data/claude/home/legacy-marker && grep -q legacy-json /state/data/claude/claude.json"
    ) | Out-Null

    Start-TestContainer

    Invoke-Docker @(
        "exec", $containerName, "bash", "-lc",
        "test -L /home/sandbox/.claude && test -d /state/data/claude/home && printf first-dir > /home/sandbox/.claude/persistence-marker"
    ) | Out-Null

    Invoke-Docker @(
        "exec", $containerName, "bash", "-lc",
        "printf '%s\n' '#!/usr/bin/env bash' 'printf ''{`"marker`":`"first-json`"}\n'' > /home/sandbox/.claude.json' > /opt/ai-sandbox/bin/claude && chmod +x /opt/ai-sandbox/bin/claude && /opt/ai-sandbox/entrypoint.sh claude"
    ) | Out-Null

    Invoke-Docker @("rm", "-f", $containerName) | Out-Null
    $containerCreated = $false
    Start-TestContainer

    $dirMarker = (Invoke-Docker @("exec", $containerName, "cat", "/home/sandbox/.claude/persistence-marker")) -join ""
    $jsonMarker = (Invoke-Docker @("exec", $containerName, "cat", "/home/sandbox/.claude.json")) -join ""
    if ($dirMarker -ne "first-dir" -or $jsonMarker -notmatch "first-json") {
        throw "Expected both Claude state locations to survive container recreation."
    }

    Invoke-Docker @(
        "exec", $containerName, "bash", "-lc",
        "printf second-dir >> /home/sandbox/.claude/persistence-marker"
    ) | Out-Null

    Invoke-Docker @(
        "exec", $containerName, "bash", "-lc",
        "printf '%s\n' '#!/usr/bin/env bash' 'printf ''{`"marker`":`"atomic-json`"}\n'' > /home/sandbox/.claude.json.tmp' 'mv -f /home/sandbox/.claude.json.tmp /home/sandbox/.claude.json' > /opt/ai-sandbox/bin/claude && chmod +x /opt/ai-sandbox/bin/claude && /opt/ai-sandbox/entrypoint.sh claude"
    ) | Out-Null

    Invoke-Docker @("rm", "-f", $containerName) | Out-Null
    $containerCreated = $false
    Start-TestContainer

    $atomicMarker = (Invoke-Docker @("exec", $containerName, "cat", "/home/sandbox/.claude.json")) -join ""
    if ($atomicMarker -notmatch "atomic-json") {
        throw "Expected an atomic replacement of Claude's top-level JSON state to survive container recreation."
    }

    Write-Host "claude-state-persistence.ps1 passed"
} catch {
    $originalError = $_
} finally {
    if ($containerCreated) {
        try {
            & docker rm -f $containerName | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "docker rm exited $LASTEXITCODE" }
        } catch {
            $cleanupErrors.Add("container $containerName`: $($_.Exception.Message)")
        }
    }

    foreach ($volume in $createdVolumes) {
        try {
            & docker volume rm $volume | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "docker volume rm exited $LASTEXITCODE" }
        } catch {
            $cleanupErrors.Add("volume $volume`: $($_.Exception.Message)")
        }
    }
}

if ($originalError) {
    if ($cleanupErrors.Count -gt 0) {
        throw "$($originalError.Exception.Message)`nCleanup errors:`n$($cleanupErrors -join "`n")"
    }
    throw $originalError
}

if ($cleanupErrors.Count -gt 0) {
    throw "Cleanup errors:`n$($cleanupErrors -join "`n")"
}
