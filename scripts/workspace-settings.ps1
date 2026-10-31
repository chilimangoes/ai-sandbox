# Workspace definitions are data. Values are passed to Docker as separate arguments.
function Get-WorkspaceSettings {
    param([pscustomobject]$Meta)
    $runArgs = New-Object System.Collections.Generic.List[string]
    $networks = New-Object System.Collections.Generic.List[string]
    $entries = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $path = Join-Path $Meta.Workspace '.ai-sandbox/workspace.config'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $lineNumber = 0
        foreach ($line in [IO.File]::ReadAllLines($path)) {
            $lineNumber++
            if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
            $separator = $line.IndexOf('=')
            if ($separator -lt 0) { throw "Invalid workspace setting in ${path}:${lineNumber}. Expected network=NAME, port=NUMBER, or env=NAME=VALUE." }
            $key = $line.Substring(0, $separator)
            $value = $line.Substring($separator + 1)
            switch -CaseSensitive ($key) {
                'network' {
                    if ($value -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$' -or $value -cin @('bridge', 'host', 'none')) {
                        throw "Invalid named Docker network in ${path}:${lineNumber}: $value"
                    }
                    $name = "network:$value"
                    $networks.Add($value)
                    $runArgs.Add('--network'); $runArgs.Add($value)
                }
                'port' {
                    if ($value -notmatch '^[0-9]{1,5}$' -or [int]$value -lt 1 -or [int]$value -gt 65535) {
                        throw "Invalid TCP port in ${path}:${lineNumber}: $value"
                    }
                    $value = ([int]$value).ToString()
                    $name = "port:$value"
                    if ([int]$value -notin @($DefaultT3ContainerPort, $DefaultAltHttpContainerPort, $DefaultAppContainerPort)) {
                        $runArgs.Add('-p'); $runArgs.Add("$($Meta.HostAddress):${value}:${value}")
                    }
                }
                'env' {
                    $separator = $value.IndexOf('=')
                    if ($separator -lt 1 -or $value.Substring(0, $separator) -cnotmatch '^[a-zA-Z_][a-zA-Z0-9_]*$') {
                        throw "Invalid environment setting in ${path}:${lineNumber}."
                    }
                    $name = $value.Substring(0, $separator)
                    if ($name -clike 'AI_SANDBOX_*' -or $name -cin @('LOCAL_UID', 'LOCAL_GID', 'HOME', 'PATH', 'USER', 'LOGNAME')) {
                        throw "Reserved environment variable in ${path}:${lineNumber}: $name"
                    }
                    $runArgs.Add('-e'); $runArgs.Add($value)
                    $name = "env:$name"
                }
                default { throw "Unknown workspace setting in ${path}:${lineNumber}: $key" }
            }
            if (-not $seen.Add($name)) { throw "Duplicate workspace setting in ${path}:${lineNumber}: $name" }
            $entries.Add("$key=$value")
        }
    }
    $sorted = $entries.ToArray()
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    $signature = if ($sorted.Count) { Get-Sha256Text -Value (($sorted -join "`n") + "`n") } else { '' }
    [pscustomobject]@{ RunArgs = $runArgs.ToArray(); Networks = $networks.ToArray(); Signature = $signature }
}

function Assert-WorkspaceNetworks {
    param([pscustomobject]$Settings)
    foreach ($network in $Settings.Networks) {
        # Capture stderr so Windows PowerShell treats a missing network as a handled error.
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $PSNativeCommandUseErrorActionPreference = $false
        try { $output = & docker network inspect $network 2>&1 }
        finally { $ErrorActionPreference = $previousPreference }
        if ($LASTEXITCODE -ne 0) {
            throw "Docker network '$network' is missing. Run the project's host bootstrap before ai-sandbox."
        }
    }
}

function Get-ContainerWorkspaceSettingsSignature {
    param([string]$Name)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    try { $value = & docker inspect --format '{{ json .Config.Labels }}' $Name 2>&1 }
    finally { $ErrorActionPreference = $previousPreference }
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect launch settings for container $Name." }
    $labels = ($value -join "`n") | ConvertFrom-Json
    $property = $labels.PSObject.Properties['ai-sandbox.workspace-settings']
    if ($property) { return [string]$property.Value }
    return ''
}

function Get-ContainerRuntimeImage {
    param([string]$Name, [string]$Tag, [string]$FallbackImageId)
    # Compare the runnable platform manifest, excluding the index's build attestations.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $value = & docker inspect --format '{{json .ImageManifestDescriptor}}' $Name 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Could not read the container image descriptor.' }
        $descriptor = ($value -join "`n") | ConvertFrom-Json
        if (-not $descriptor.digest) {
            $currentId = Get-ImageId -Tag $Tag
            if (-not $currentId) { throw 'Could not inspect the workspace image.' }
            return [pscustomobject]@{ Running = $FallbackImageId; Current = $currentId }
        }
        $platform = "$($descriptor.platform.os)/$($descriptor.platform.architecture)"
        if ($descriptor.platform.variant) { $platform += "/$($descriptor.platform.variant)" }
        $current = & docker image inspect --platform $platform --format '{{.Id}}' $Tag 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the workspace platform image.' }
        [pscustomobject]@{ Running = $descriptor.digest; Current = ($current -join "`n").Trim() }
    } finally { $ErrorActionPreference = $previousPreference }
}

function Get-WorkspaceTrustPath {
    param([pscustomobject]$Meta)
    Join-Path $HOME ".ai-sandbox/trusted-workspaces/$($Meta.Hash)"
}

function Set-WorkspaceTrust {
    param([pscustomobject]$Meta)
    $path = Get-WorkspaceTrustPath -Meta $Meta
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path, $Meta.Workspace)
    Write-Host "Trusted sandbox build and launch definitions in $($Meta.Workspace). Revoke with ai-sandbox untrust."
}

function Assert-WorkspaceTrust {
    param([pscustomobject]$Meta)
    if (-not ((Test-Path -LiteralPath (Join-Path $Meta.Workspace '.ai-sandbox/Dockerfile') -PathType Leaf) -or
        (Test-Path -LiteralPath (Join-Path $Meta.Workspace '.ai-sandbox/workspace.config') -PathType Leaf))) { return }
    $path = Get-WorkspaceTrustPath -Meta $Meta
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and [IO.File]::ReadAllText($path).TrimEnd("`r", "`n") -ceq $Meta.Workspace) { return }
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        throw "Workspace customization requires approval. Run ai-sandbox trust in $($Meta.Workspace), then retry."
    }
    $answer = Read-Host "Trust sandbox build and launch definitions in $($Meta.Workspace), including future edits? [y/N]"
    if ($answer -notin @('y', 'yes')) { throw 'Workspace trust declined.' }
    Set-WorkspaceTrust -Meta $Meta
}

# File locks are released by the OS if the launcher exits or is interrupted.
function Enter-LauncherLock {
    param([string]$Name)
    $directory = Join-Path $HOME '.ai-sandbox/locks'
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $path = Join-Path $directory "$Name.lock"
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    do {
        try { return [IO.File]::Open($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) { throw "Timed out waiting for launcher lock: $Name" }
            Start-Sleep -Milliseconds 200
        }
    } while ($true)
}

function Initialize-WorkspaceImage {
    param([pscustomobject]$Meta, [switch]$Refresh)
    $dockerfile = Join-Path $Meta.Workspace '.ai-sandbox/Dockerfile'
    $baseLock = Enter-LauncherLock -Name 'base-image'
    try {
        if (-not (Get-ImageId -Tag $ImageTag) -or $Refresh) {
            Build-Image -Pull -Refresh:($update -or $rebuild)
        }
        if (Test-Path -LiteralPath $dockerfile -PathType Leaf) {
            $baseId = Get-ImageId -Tag $ImageTag
            if (-not $baseId) { throw "Image $ImageTag not found after build." }
            $baseRef = 'ai-sandbox-base:' + ($baseId -replace '^sha256:', '')
            & docker tag $baseId $baseRef
            if ($LASTEXITCODE -ne 0) { throw 'Could not tag the installed sandbox base image.' }
        }
    } finally { $baseLock.Dispose() }
    if (-not (Test-Path -LiteralPath $dockerfile -PathType Leaf)) { return }
    $tag = "ai-sandbox-workspace:$($Meta.Hash)"
    $buildArgs = @('build', '-t', $tag, '--file', $dockerfile, '--build-arg', "AI_SANDBOX_BASE_IMAGE=$baseRef")
    if ($Refresh) { $buildArgs += '--no-cache' }
    $buildArgs += (Join-Path $Meta.Workspace '.ai-sandbox')
    Write-Host "Building workspace image $tag"
    & docker @buildArgs
    if ($LASTEXITCODE -ne 0) { throw 'Workspace image build failed. The existing container has not been replaced.' }
    $script:ImageTag = $tag
}
