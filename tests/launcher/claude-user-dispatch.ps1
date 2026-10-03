[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$stubPath = Join-Path $repoRoot "tests\launcher\fixtures\claude-user-stub.sh"
$suffix = [guid]::NewGuid().ToString("N")
$containerName = "ai-sandbox-claude-user-$suffix"
$expectedUid = "12345"
$expectedGid = "12345"
$containerCreated = $false
$originalError = $null
$cleanupError = $null

function Invoke-Docker {
    param([string[]]$DockerArgs)

    $previousErrorActionPreference = $ErrorActionPreference
    $previousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & docker @DockerArgs 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
    }

    if ($exitCode -ne 0) {
        $details = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
        throw "docker $($DockerArgs -join ' ') exited $exitCode. $details"
    }

    return $output
}

try {
    Invoke-Docker @(
        "run", "-d", "--name", $containerName,
        "-e", "LOCAL_UID=$expectedUid",
        "-e", "LOCAL_GID=$expectedGid",
        "ai-sandbox:latest", "daemon"
    ) | Out-Null
    $containerCreated = $true

    Invoke-Docker @("cp", $stubPath, "${containerName}:/tmp/claude-user-stub.sh") | Out-Null
    Invoke-Docker @(
        "exec", $containerName, "bash", "-lc",
        "cp /tmp/claude-user-stub.sh /opt/ai-sandbox/bin/claude && chmod +x /opt/ai-sandbox/bin/claude"
    ) | Out-Null

    $rootShellOutput = (Invoke-Docker @(
        "exec", $containerName, "claude", "--dangerously-skip-permissions"
    )) -join "`n"
    if ($rootShellOutput -notmatch "(?m)^uid=$expectedUid`$") {
        throw "Expected the normal root shell to dispatch Claude as UID $expectedUid. Output: $rootShellOutput"
    }

    $sandboxShellOutput = (Invoke-Docker @(
        "exec", "--user", "sandbox", $containerName, "claude"
    )) -join "`n"
    if ($sandboxShellOutput -notmatch "(?m)^uid=$expectedUid`$") {
        throw "Expected a sandbox shell to dispatch Claude without root-only initialization. Output: $sandboxShellOutput"
    }

    $stateOwner = (Invoke-Docker @(
        "exec", $containerName, "stat", "-c", "%u", "/state/data/claude/claude.json"
    )) -join ""
    if ($stateOwner.Trim() -ne $expectedUid) {
        throw "Expected Claude state to belong to UID $expectedUid, but it belongs to UID $($stateOwner.Trim())."
    }

    Write-Host "claude-user-dispatch.ps1 passed"
} catch {
    $originalError = $_
} finally {
    if ($containerCreated) {
        try {
            & docker rm -f $containerName | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "docker rm exited $LASTEXITCODE" }
        } catch {
            $cleanupError = $_
        }
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
