[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$suffix = [guid]::NewGuid().ToString("N")
$containerName = "ai-sandbox-claude-first-run-$suffix"
$volumes = @(
    "ai-sandbox-claude-first-run-config-$suffix",
    "ai-sandbox-claude-first-run-auth-$suffix",
    "ai-sandbox-claude-first-run-data-$suffix",
    "ai-sandbox-claude-first-run-cache-$suffix"
)
$createdVolumes = New-Object System.Collections.Generic.List[string]
$originalError = $null
$cleanupErrors = New-Object System.Collections.Generic.List[string]

try {
    foreach ($volume in $volumes) {
        & docker volume create $volume | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create test volume $volume."
        }
        $createdVolumes.Add($volume)
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $previousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & docker run --name $containerName `
            -v "$($volumes[0]):/state/config" `
            -v "$($volumes[1]):/state/auth" `
            -v "$($volumes[2]):/state/data" `
            -v "$($volumes[3]):/state/cache" `
            ai-sandbox:latest claude doctor 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
    }

    if ($exitCode -ne 0) {
        throw "Claude failed on first run with exit code ${exitCode}:`n$($output -join "`n")"
    }

    if (($output -join "`n") -match 'Unexpected EOF|configuration file .* corrupted') {
        throw "Claude reported an invalid empty configuration on first run."
    }

    $jsonType = & docker run --rm --entrypoint jq `
        -v "$($volumes[2]):/state/data" `
        ai-sandbox:latest -r type /state/data/claude/claude.json
    if ($LASTEXITCODE -ne 0 -or ($jsonType -join "").Trim() -ne "object") {
        throw "Expected Claude to persist a valid top-level JSON object after first run."
    }

    Write-Host "claude-first-run.ps1 passed"
} catch {
    $originalError = $_
} finally {
    try {
        $existing = & docker ps -a --filter "name=^/${containerName}$" --format "{{.Names}}" 2>$null
        if ($existing -eq $containerName) {
            & docker rm -f $containerName | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "docker rm exited $LASTEXITCODE" }
        }
    } catch {
        $cleanupErrors.Add("container $containerName`: $($_.Exception.Message)")
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
