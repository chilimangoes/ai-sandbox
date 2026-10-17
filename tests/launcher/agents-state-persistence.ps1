[CmdletBinding()]
param([string]$Engine = $(if ($env:AI_SANDBOX_ENGINE) { $env:AI_SANDBOX_ENGINE } else { 'auto' }))

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../lib/runtime-engine.ps1")

$suffix = "$script:EngineCommand-$([guid]::NewGuid().ToString('N'))"
$containerName = "ai-sandbox-agents-state-$suffix"
$volumes = @(
    "ai-sandbox-agents-config-$suffix",
    "ai-sandbox-agents-auth-$suffix",
    "ai-sandbox-agents-data-$suffix",
    "ai-sandbox-agents-cache-$suffix"
)
$createdVolumes = New-Object System.Collections.Generic.List[string]
$containerCreated = $false
$originalError = $null
$cleanupErrors = New-Object System.Collections.Generic.List[string]

function Invoke-TestCommand {
    param([string[]]$EngineArgs)
    $output = Invoke-TestEngine @EngineArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
        throw "$script:EngineCommand $($EngineArgs -join ' ') exited $LASTEXITCODE. $details"
    }
    return $output
}

function Start-TestContainer {
    Invoke-TestCommand @(
        "run", "-d", "--name", $containerName,
        "-v", "$($volumes[0]):/state/config",
        "-v", "$($volumes[1]):/state/auth",
        "-v", "$($volumes[2]):/state/data",
        "-v", "$($volumes[3]):/state/cache",
        "ai-sandbox:latest", "daemon"
    ) | Out-Null
    $script:containerCreated = $true
    Invoke-TestCommand @("exec", $containerName, "/opt/ai-sandbox/entrypoint.sh", "true") | Out-Null
}

try {
    foreach ($volume in $volumes) {
        Invoke-TestCommand @("volume", "create", $volume) | Out-Null
        $createdVolumes.Add($volume)
    }

    Start-TestContainer

    Invoke-TestCommand @(
        "exec", $containerName, "bash", "-lc",
        "test -L /home/sandbox/.agents && readlink /home/sandbox/.agents | grep -qx /state/data/agents && printf persistent-agents-state > /home/sandbox/.agents/persistence-marker && /opt/ai-sandbox/bootstrap/init-state.sh && grep -qx persistent-agents-state /home/sandbox/.agents/persistence-marker"
    ) | Out-Null

    Invoke-TestCommand @("rm", "-f", $containerName) | Out-Null
    $containerCreated = $false
    Start-TestContainer

    Invoke-TestCommand @(
        "exec", $containerName, "bash", "-lc",
        "test -L /home/sandbox/.agents && readlink /home/sandbox/.agents | grep -qx /state/data/agents && grep -qx persistent-agents-state /home/sandbox/.agents/persistence-marker && grep -qx persistent-agents-state /state/data/agents/persistence-marker"
    ) | Out-Null

    Write-Host "agents-state-persistence.ps1 passed"
} catch {
    $originalError = $_
} finally {
    if ($containerCreated) {
        try {
            Invoke-TestEngine rm -f $containerName | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "$script:EngineCommand rm exited $LASTEXITCODE" }
        } catch {
            $cleanupErrors.Add("container $containerName`: $($_.Exception.Message)")
        }
    }

    foreach ($volume in $createdVolumes) {
        try {
            Invoke-TestEngine volume rm $volume | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "$script:EngineCommand volume rm exited $LASTEXITCODE" }
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
