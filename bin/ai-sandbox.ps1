[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ArgsList
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptRoot
$ImageTag = "ai-sandbox:latest"
$DefaultT3ContainerPort = 3773
$DefaultCodeNomadContainerPort = 9899
$DefaultPaseoContainerPort = 6767
$DefaultAltHttpContainerPort = 8080
$DefaultAppContainerPort = 3000

function Write-Usage {
    @"
Usage: ai-sandbox [--engine auto|docker|podman] [--update] [--rebuild] [--add-folder <path> [--as <name>] [--global|--local] [--read-only|--read-write] [--yes]] [shell|codex|claude|agy|copilot|opencode|cursor|cursor-agent|t3|codenomad|paseo|doctor|stop|rm|reset-config|reset-state]
"@
}

function Invoke-Engine {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$EngineArgs)
    # Windows PowerShell turns redirected native stderr into ErrorRecords.
    # Let callers use the exit code rather than terminating on diagnostics.
    $ErrorActionPreference = "Continue"
    $PSNativeCommandUseErrorActionPreference = $false
    & $script:EngineCommand @EngineArgs
}

function Invoke-EngineQuery {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$EngineArgs)
    $ErrorActionPreference = "Continue"
    $PSNativeCommandUseErrorActionPreference = $false
    $output = @(Invoke-Engine @EngineArgs 2>&1)
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        Output = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
        ErrorOutput = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
        ExitCode = $exitCode
    }
}

function Test-EngineHealthy {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { return $false }
    try {
        $ErrorActionPreference = "Continue"
        $PSNativeCommandUseErrorActionPreference = $false
        & $Name version *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Resolve-Engine {
    param([string]$RequestedEngine)
    if ($RequestedEngine -cnotin @("auto", "docker", "podman")) {
        throw "Invalid engine '$RequestedEngine'. Expected auto, docker, or podman."
    }
    if ($RequestedEngine -cne "auto") {
        if (-not (Test-EngineHealthy -Name $RequestedEngine)) {
            $guidance = if ($RequestedEngine -eq 'podman') { ' Inspect with `podman machine list` and `podman system connection list`; start the intended stopped machine with `podman machine start <name>`.' } else { '' }
            throw "Selected engine '$RequestedEngine' is unavailable or unhealthy.$guidance"
        }
        return $RequestedEngine
    }
    foreach ($candidate in @("docker", "podman")) {
        if (Test-EngineHealthy -Name $candidate) { return $candidate }
    }
    throw "No healthy container engine is available. Start Docker, or inspect Podman with ``podman machine list`` and ``podman system connection list``; start the intended stopped machine with ``podman machine start <name>``."
}

function Get-WorkspaceMeta {
    param([string]$WorkspacePath)

    $fullPath = [System.IO.Path]::GetFullPath($WorkspacePath)
    $leaf = Split-Path -Leaf $fullPath
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        $leaf = "workspace"
    }

    $slug = ($leaf.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = "workspace"
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($fullPath.ToLowerInvariant())
        $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
    } finally {
        $sha.Dispose()
    }

    $suffix = $hash.Substring(0, 12)
    $loopbackOctet2 = 64 + ([Convert]::ToInt32($hash.Substring(0, 2), 16) % 64)
    $loopbackOctet3 = [Convert]::ToInt32($hash.Substring(2, 2), 16)
    $loopbackOctet4 = 1 + ([Convert]::ToInt32($hash.Substring(4, 2), 16) % 254)
    $hostAddress = "127.$loopbackOctet2.$loopbackOctet3.$loopbackOctet4"

    [pscustomobject]@{
        Workspace = $fullPath
        Slug = $slug
        Hash = $suffix
        HostAddress = $hostAddress
        ContainerWorkspaceRoot = "/workspace"
        ContainerWorkspacePath = "/workspace/$slug"
        Container = "ai-sandbox-$slug-$suffix"
        ConfigVolume = "ai-sandbox-$slug-$suffix-config"
        AuthVolume = "ai-sandbox-$slug-$suffix-auth"
        DataVolume = "ai-sandbox-$slug-$suffix-data"
        CacheVolume = "ai-sandbox-$slug-$suffix-cache"
    }
}

function Test-ContainerFolderName {
    param([string]$Name)
    return -not [string]::IsNullOrWhiteSpace($Name) -and
        $Name.Trim() -eq $Name -and
        $Name -notmatch '[\\/:\*\?"<>\|]'
}

function Split-SupplementalFolderLine {
    param(
        [string]$Line,
        [string]$Path,
        [int]$LineNumber
    )

    $trimmed = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
        return $null
    }

    $mode = "ro"
    $withoutMode = $trimmed
    $modeSeparator = $trimmed.LastIndexOf('|')
    if ($modeSeparator -ge 0) {
        $candidateMode = $trimmed.Substring($modeSeparator + 1)
        if ($candidateMode -eq "ro" -or $candidateMode -eq "rw") {
            $mode = $candidateMode
            $withoutMode = $trimmed.Substring(0, $modeSeparator)
        }
    }

    $nameSeparator = $withoutMode.LastIndexOf('|')
    if ($nameSeparator -lt 0) {
        throw "Invalid supplemental folder entry in ${Path}:${LineNumber}. Expected host_path|container_name|mode."
    }

    $hostPath = $withoutMode.Substring(0, $nameSeparator)
    $name = $withoutMode.Substring($nameSeparator + 1)
    if (-not (Test-ContainerFolderName -Name $name)) {
        throw "Invalid supplemental folder target '$name' in ${Path}:${LineNumber}. It must be one path segment and cannot contain / \ : * ? `" < > |."
    }

    if ($mode -ne "ro" -and $mode -ne "rw") {
        throw "Invalid supplemental folder mode '$mode' in ${Path}:${LineNumber}. Expected ro or rw."
    }

    [pscustomobject]@{
        HostPath = [System.IO.Path]::GetFullPath($hostPath)
        Name = $name
        Mode = $mode
        Source = $Path
    }
}

function Read-SupplementalFolderConfig {
    param(
        [string]$Path,
        [string]$Scope
    )

    $entries = @()
    if (-not (Test-Path -LiteralPath $Path)) {
        return $entries
    }

    $seen = @{}
    $lines = @(Get-Content -LiteralPath $Path)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $entry = Split-SupplementalFolderLine -Line $lines[$i] -Path $Path -LineNumber ($i + 1)
        if (-not $entry) { continue }
        if ($seen.ContainsKey($entry.Name)) {
            throw "Duplicate supplemental folder target /supplemental/$($entry.Name) in $scope config: $Path"
        }
        if (-not (Test-Path -LiteralPath $entry.HostPath -PathType Container)) {
            throw "Supplemental folder path from $scope config does not exist or is not a directory: $($entry.HostPath)"
        }
        $seen[$entry.Name] = $true
        $entries += $entry
    }
    return $entries
}

function Get-Sha256Text {
    param([string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha.Dispose()
    }
}

function Get-SupplementalFolderMounts {
    param([string]$WorkspacePath)

    $globalPath = Join-Path $HOME ".ai-sandbox\supplemental-folders.config"
    $localPath = Join-Path $WorkspacePath ".ai-sandbox\supplemental-folders.config"
    $globalEntries = Read-SupplementalFolderConfig -Path $globalPath -Scope "global"
    $localEntries = Read-SupplementalFolderConfig -Path $localPath -Scope "local"
    $byName = [ordered]@{}
    $warnings = New-Object System.Collections.Generic.List[string]

    foreach ($entry in $globalEntries) {
        $byName[$entry.Name] = $entry
    }

    foreach ($entry in $localEntries) {
        if ($byName.Contains($entry.Name)) {
            $globalEntry = $byName[$entry.Name]
            $warnings.Add("local supplemental folder overrides global mapping for /supplemental/$($entry.Name): using $($entry.HostPath), ignoring $($globalEntry.HostPath)")
        }
        $byName[$entry.Name] = $entry
    }

    $mounts = @($byName.Values)
    $signatureText = (($mounts | Sort-Object Name | ForEach-Object { "$($_.HostPath)|$($_.Name)|$($_.Mode)" }) -join "`n")
    [pscustomobject]@{
        Mounts = $mounts
        Signature = Get-Sha256Text -Value $signatureText
        Warnings = $warnings
    }
}

function Get-ServiceDefinitions {
    @(
        [pscustomobject]@{ Name = 'T3'; Port = $DefaultT3ContainerPort; Url = 'URL' }
        [pscustomobject]@{ Name = 'CODENOMAD'; Port = $DefaultCodeNomadContainerPort; Url = 'URL' }
        [pscustomobject]@{ Name = 'PASEO'; Port = $DefaultPaseoContainerPort; Url = 'ADDRESS' }
        [pscustomobject]@{ Name = 'ALT_HTTP'; Port = $DefaultAltHttpContainerPort; Url = 'URL' }
        [pscustomobject]@{ Name = 'APP'; Port = $DefaultAppContainerPort; Url = 'URL' }
    )
}

function Get-CandidateEndpoints {
    param([pscustomobject]$Meta, [int]$Attempt = 0)
    $services = @(Get-ServiceDefinitions)
    $initial = [Convert]::ToUInt32($Meta.Hash.Substring(0, 8), 16) % 6000
    for ($index = 0; $index -lt $services.Count; $index++) {
        $hostPort = $services[$index].Port
        $address = $Meta.HostAddress
        if ($script:EngineCommand -eq 'podman') {
            $address = '127.0.0.1'
            $hostPort = 20000 + 5 * (($initial + $Attempt) % 6000) + $index
        }
        [pscustomobject]@{ ContainerPort = $services[$index].Port; HostAddress = $address; HostPort = [int]$hostPort }
    }
}

function Test-PortBlockAvailable {
    param([object[]]$Endpoints)
    $listeners = New-Object System.Collections.Generic.List[System.Net.Sockets.TcpListener]
    try {
        foreach ($endpoint in $Endpoints) {
            $listener = New-Object System.Net.Sockets.TcpListener ([Net.IPAddress]::Parse($endpoint.HostAddress)), $endpoint.HostPort
            $listeners.Add($listener)
            $listener.Server.ExclusiveAddressUse = $true
            $listener.Start()
        }
        return $true
    } catch [System.Net.Sockets.SocketException] {
        return $false
    } finally {
        foreach ($listener in $listeners) { $listener.Stop() }
    }
}

function Get-EndpointEnvironment {
    param([pscustomobject]$Meta, [object[]]$Endpoints)
    foreach ($service in @(Get-ServiceDefinitions)) {
        $endpoint = @($Endpoints | Where-Object { $_.ContainerPort -eq $service.Port })
        if ($endpoint.Count -ne 1) { throw "Missing or ambiguous mapping for container port $($service.Port)." }
        $address = "$($endpoint[0].HostAddress):$($endpoint[0].HostPort)"
        $value = if ($service.Url -eq 'URL') { "http://$address" } else { $address }
        "AI_SANDBOX_$($service.Name)_PORT=$($service.Port)"
        "AI_SANDBOX_HOST_$($service.Name)_PORT=$($endpoint[0].HostPort)"
        "AI_SANDBOX_$($service.Name)_$($service.Url)=$value"
    }
    "AI_SANDBOX_WORKSPACE_PATH=$($Meta.ContainerWorkspacePath)"
}

function Start-Container {
    param([pscustomobject]$Meta, [pscustomobject]$SupplementalFolders)
    $attemptLimit = if ($script:EngineCommand -eq 'podman') { 32 } else { 1 }
    for ($attempt = 0; $attempt -lt $attemptLimit; $attempt++) {
        $endpoints = @(Get-CandidateEndpoints -Meta $Meta -Attempt $attempt)
        if ($script:EngineCommand -eq 'podman' -and -not (Test-PortBlockAvailable -Endpoints $endpoints)) { continue }
        $engineArgs = @(
            'run', '-d', '--name', $Meta.Container,
            '--hostname', "$($Meta.Slug.Substring(0, [Math]::Min(50, $Meta.Slug.Length)).TrimEnd('-'))-$($Meta.Hash)",
            '--label', "ai-sandbox.workspace=$($Meta.Workspace)",
            '--label', "ai-sandbox.hash=$($Meta.Hash)",
            '--label', "ai-sandbox.supplemental-folders=$($SupplementalFolders.Signature)"
        )
        foreach ($endpoint in $endpoints) { $engineArgs += @('-p', "$($endpoint.HostAddress):$($endpoint.HostPort):$($endpoint.ContainerPort)") }
        foreach ($value in @(Get-EndpointEnvironment -Meta $Meta -Endpoints $endpoints)) { $engineArgs += @('-e', $value) }
        $engineArgs += @(
            '-e', 'LOCAL_UID=1000', '-e', 'LOCAL_GID=1000',
            '-v', "$($Meta.Workspace):$($Meta.ContainerWorkspacePath)",
            '-v', "$($Meta.ConfigVolume):/state/config", '-v', "$($Meta.AuthVolume):/state/auth",
            '-v', "$($Meta.DataVolume):/state/data", '-v', "$($Meta.CacheVolume):/state/cache"
        )
        foreach ($mount in $SupplementalFolders.Mounts) { $engineArgs += @('-v', "$($mount.HostPath):/supplemental/$($mount.Name):$($mount.Mode)") }
        $engineArgs += @($ImageTag, 'daemon')
        $ErrorActionPreference = 'Continue'
        $output = @(Invoke-Engine @engineArgs 2>&1)
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($exitCode -eq 0) { return }
        $message = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
        if ($script:EngineCommand -ne 'podman' -or $message -notmatch '(?i)address already in use|port is already allocated|ports are not available|bind.*in use') {
            throw "Container creation failed (exit code $exitCode): $($message.Trim())"
        }
        # A failed run can leave its named container behind. Remove only that exact resource.
        Remove-ContainerIfExists -Name $Meta.Container
    }
    throw 'No available Podman localhost port block after 32 attempts in 20000-49999.'
}

function Get-ContainerInspection {
    param([string]$Name)
    $result = Invoke-EngineQuery inspect $Name
    if ($result.ExitCode -ne 0) {
        if (Test-ContainerExists -Name $Name -FailOnError) { throw "Could not inspect container $Name (exit code $($result.ExitCode)): $($result.ErrorOutput -join ' ')" }
        return $null
    }
    try { $items = @(($result.Output -join "`n") | ConvertFrom-Json) } catch { throw "Malformed container inspection for $Name." }
    if ($items.Count -ne 1 -or $items[0].Name -isnot [string] -or
        $items[0].Name.TrimStart('/') -cne $Name.TrimStart('/') -or
        $items[0].Image -isnot [string] -or [string]::IsNullOrWhiteSpace($items[0].Image) -or
        $items[0].State.Running -isnot [bool] -or $items[0].Config -isnot [pscustomobject]) {
        throw "Invalid container inspection for $Name."
    }
    return $items[0]
}

function Get-InspectedEndpoints {
    param([object]$Inspection)
    foreach ($service in @(Get-ServiceDefinitions)) {
        $key = "$($service.Port)/tcp"
        $bindings = @($Inspection.NetworkSettings.Ports.$key | Where-Object { $null -ne $_ })
        if ($bindings.Count -eq 0 -and -not $Inspection.State.Running) { $bindings = @($Inspection.HostConfig.PortBindings.$key | Where-Object { $null -ne $_ }) }
        $ipv4 = @()
        foreach ($binding in $bindings) {
            $parsed = $null
            $number = 0
            if (-not [Net.IPAddress]::TryParse("$($binding.HostIp)", [ref]$parsed) -or -not [int]::TryParse("$($binding.HostPort)", [ref]$number) -or $number -lt 1 -or $number -gt 65535) { return }
            if ($parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) { $ipv4 += [pscustomobject]@{ ContainerPort = $service.Port; HostAddress = $parsed.ToString(); HostPort = $number } }
        }
        if ($ipv4.Count -ne 1) { return }
        $ipv4[0]
    }
}

function Test-CompatibleEndpoints {
    param([pscustomobject]$Meta, [object[]]$Endpoints)
    $expected = @(Get-CandidateEndpoints -Meta $Meta)
    if ($Endpoints.Count -ne 5) { return $false }
    for ($i = 0; $i -lt 5; $i++) {
        if ($Endpoints[$i].ContainerPort -ne $expected[$i].ContainerPort -or $Endpoints[$i].HostAddress -cne $expected[$i].HostAddress) { return $false }
        if ($script:EngineCommand -eq 'docker' -and $Endpoints[$i].HostPort -ne $expected[$i].HostPort) { return $false }
        if ($script:EngineCommand -eq 'podman' -and $Endpoints[$i].HostPort -ne ($Endpoints[0].HostPort + $i)) { return $false }
    }
    if ($script:EngineCommand -eq 'podman') {
        $first = $Endpoints[0].HostPort
        $initial = [Convert]::ToUInt32($Meta.Hash.Substring(0, 8), 16) % 6000
        if ($first -lt 20000 -or $first -gt 49995 -or ($first - 20000) % 5 -ne 0) { return $false }
        if (((($first - 20000) / 5 - $initial + 6000) % 6000) -ge 32) { return $false }
    }
    return $true
}

function Confirm-PublishedEndpoints {
    param([string]$Name, [object[]]$Endpoints)
    foreach ($endpoint in $Endpoints) {
        $result = Invoke-EngineQuery port $Name "$($endpoint.ContainerPort)/tcp"
        $actual = @($result.Output | ForEach-Object { "$_".Trim() })
        if ($result.ExitCode -ne 0 -or $actual -cnotcontains "$($endpoint.HostAddress):$($endpoint.HostPort)") {
            throw "Published endpoint disagrees with structured inspection for $Name port $($endpoint.ContainerPort): expected $($endpoint.HostAddress):$($endpoint.HostPort), exit $($result.ExitCode), output '$($actual -join ', ')', stderr '$($result.ErrorOutput -join ' ')'."
        }
    }
}

function Test-ContainerExists {
    param([string]$Name, [switch]$FailOnError)
    $result = Invoke-EngineQuery ps -a --format "{{.Names}}"
    if ($FailOnError -and $result.ExitCode -ne 0) {
        throw "Could not list containers in the selected engine (exit code $($result.ExitCode))."
    }
    return $result.ExitCode -eq 0 -and
        (@($result.Output | ForEach-Object { "$($_)".Trim().TrimStart('/') }) -ccontains $Name.TrimStart('/'))
}

function Test-ContainerRunning {
    param([string]$Name)
    $result = Invoke-EngineQuery ps --format "{{.Names}}"
    return $result.ExitCode -eq 0 -and
        (@($result.Output | ForEach-Object { "$($_)".Trim().TrimStart('/') }) -ccontains $Name.TrimStart('/'))
}

function Get-ContainerImageId {
    param([string]$Name)
    $inspection = Get-ContainerInspection -Name $Name
    if (-not $inspection) { return $null }
    return ("$($inspection.Image)" -replace '^sha256:', '')
}

function Get-ContainerSupplementalFolderSignature {
    param([string]$Name)
    $inspection = Get-ContainerInspection -Name $Name
    if (-not $inspection) { return $null }
    $value = $inspection.Config.Labels.'ai-sandbox.supplemental-folders'
    if ($value -is [string]) { return $value }
    return $null
}

function Get-ImageId {
    param([string]$Tag)
    $result = Invoke-EngineQuery image inspect $Tag
    if ($result.ExitCode -ne 0) {
        $listing = Invoke-EngineQuery image ls --format '{{.Repository}}:{{.Tag}}'
        if ($listing.ExitCode -ne 0) { throw "Could not query images in the selected engine (exit code $($listing.ExitCode)): $($listing.ErrorOutput -join ' ')" }
        $aliases = @($Tag)
        if ($script:EngineCommand -eq 'podman' -and $Tag -notmatch '/') { $aliases += "localhost/$Tag" }
        foreach ($alias in $aliases) {
            if (@($listing.Output | ForEach-Object { "$_".Trim() }) -ccontains $alias) { throw "Could not inspect image $Tag (exit code $($result.ExitCode)): $($result.ErrorOutput -join ' ')" }
        }
        return $null
    }
    try { $items = @(($result.Output -join "`n") | ConvertFrom-Json) } catch { throw "Malformed image inspection for $Tag." }
    if ($items.Count -ne 1 -or $items[0].Id -isnot [string] -or [string]::IsNullOrWhiteSpace($items[0].Id)) { throw "Invalid image inspection for $Tag." }
    return ("$($items[0].Id)" -replace '^sha256:', '')
}

function Ensure-Volume {
    param([string]$Name)

    # Use `volume ls` rather than `inspect` so a missing volume does not
    # emit an error on Windows PowerShell 5.1.
    $existing = Invoke-Engine volume ls --format "{{.Name}}"
    if ($LASTEXITCODE -ne 0) { throw "Could not list volumes in the selected engine." }
    if (@($existing | ForEach-Object { "$($_)".Trim() }) -cnotcontains $Name) {
        Invoke-Engine volume create $Name | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not create volume $Name." }
    }
    $result = Invoke-EngineQuery volume inspect $Name
    if ($result.ExitCode -ne 0) { throw "Could not inspect volume $Name." }
    try { $volumes = @(($result.Output -join "`n") | ConvertFrom-Json) } catch { throw "Malformed volume inspection for $Name." }
    if ($volumes.Count -ne 1 -or $volumes[0].Name -cne $Name) { throw "Invalid volume inspection for $Name." }
}

function Build-Image {
    param([switch]$Pull, [switch]$Refresh)
    $buildArgs = @("build", "-t", $ImageTag)
    if ($Pull) {
        $buildArgs += $(if ($script:EngineCommand -eq 'podman') { '--pull=always' } else { '--pull' })
    }
    if ($Refresh) {
        $buildArgs += "--no-cache"
    }
    $buildArgs += $RepoRoot
    Invoke-Engine @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Sandbox image build failed (exit code $LASTEXITCODE). The existing container has not been replaced."
    }
}

function Remove-ContainerIfExists {
    param([string]$Name)
    if (Test-ContainerExists -Name $Name -FailOnError) {
        Invoke-Engine rm -f $Name | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to remove container $Name (exit code $LASTEXITCODE)." }
    }
}

function Remove-VolumeIfExists {
    param([string]$Name)
    $result = Invoke-EngineQuery volume ls --format "{{.Name}}"
    if ($result.ExitCode -ne 0) { throw "Could not list volumes in the selected engine (exit code $($result.ExitCode))." }
    if (@($result.Output | ForEach-Object { "$($_)".Trim() }) -ccontains $Name) {
        Invoke-Engine volume rm $Name | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to remove volume $Name (exit code $LASTEXITCODE)." }
    }
}

function Get-ExistingHostPort {
    param(
        [string]$Name,
        [int]$ContainerPort
    )

    $result = Invoke-EngineQuery port $Name $ContainerPort/tcp
    $stdout = $result.Output -join "`n"
    $exitCode = $result.ExitCode

    if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stdout)) {
        return $null
    }

    foreach ($line in ($stdout -split "`r?`n")) {
        if ($line -match ':(\d+)$') {
            return [int]$Matches[1]
        }
    }

    return $null
}

function Ensure-Container {
    param([pscustomobject]$Meta, [pscustomobject]$SupplementalFolders, [switch]$ForceRecreate)
    $currentImageId = Get-ImageId -Tag $ImageTag
    if (-not $currentImageId) { throw "Image $ImageTag does not exist." }
    $inspection = Get-ContainerInspection -Name $Meta.Container
    if ($inspection) {
        $endpoints = @(Get-InspectedEndpoints -Inspection $inspection)
        if ($ForceRecreate -or
            ("$($inspection.Image)" -replace '^sha256:', '') -cne $currentImageId -or
            $inspection.Config.Labels.'ai-sandbox.supplemental-folders' -cne $SupplementalFolders.Signature -or
            -not (Test-CompatibleEndpoints -Meta $Meta -Endpoints $endpoints)) {
            Remove-ContainerIfExists -Name $Meta.Container
            $inspection = $null
        }
    }
    foreach ($volume in @($Meta.ConfigVolume, $Meta.AuthVolume, $Meta.DataVolume, $Meta.CacheVolume)) { Ensure-Volume -Name $volume }
    if (-not $inspection) { Start-Container -Meta $Meta -SupplementalFolders $SupplementalFolders }
    elseif (-not $inspection.State.Running) {
        Invoke-Engine start $Meta.Container | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to start existing container $($Meta.Container)." }
    }
    $inspection = Get-ContainerInspection -Name $Meta.Container
    if (-not $inspection -or -not $inspection.State.Running) { throw "Container $($Meta.Container) is not running after startup." }
    if (("$($inspection.Image)" -replace '^sha256:', '') -cne $currentImageId -or
        $inspection.Config.Labels.'ai-sandbox.supplemental-folders' -cne $SupplementalFolders.Signature) {
        throw "Container $($Meta.Container) has incompatible image or mount metadata after startup."
    }
    $endpoints = @(Get-InspectedEndpoints -Inspection $inspection)
    if (-not (Test-CompatibleEndpoints -Meta $Meta -Endpoints $endpoints)) { throw "Container $($Meta.Container) has incompatible published endpoints after startup." }
    Confirm-PublishedEndpoints -Name $Meta.Container -Endpoints $endpoints
    $Meta | Add-Member -NotePropertyName Endpoints -NotePropertyValue $endpoints -Force
}

function Exec-InContainer {
    param([pscustomobject]$Meta, [string[]]$CommandArgs, [switch]$Interactive)
    $engineArgs = @('exec')
    if ($Interactive) { $engineArgs += '-it' }
    if (-not $Meta.Endpoints) { throw 'Container endpoints have not been inspected.' }
    foreach ($value in @(Get-EndpointEnvironment -Meta $Meta -Endpoints $Meta.Endpoints)) { $engineArgs += @('-e', $value) }
    $engineArgs += @($Meta.Container, '/opt/ai-sandbox/entrypoint.sh')
    $engineArgs += $CommandArgs
    Invoke-Engine @engineArgs
}

$update = $false
$rebuild = $false
$requestedEngine = if ([string]::IsNullOrWhiteSpace($env:AI_SANDBOX_ENGINE)) { "auto" } else { $env:AI_SANDBOX_ENGINE }
$positionals = New-Object System.Collections.Generic.List[string]
$addFolderArgs = $null

for ($i = 0; $i -lt $ArgsList.Count; $i++) {
    switch ($ArgsList[$i]) {
        "--help" {
            Write-Usage
            exit 0
        }
        "--update" {
            $update = $true
        }
        "--rebuild" {
            $rebuild = $true
        }
        "--engine" {
            if ($i + 1 -ge $ArgsList.Count) { throw "Missing engine for --engine. Expected auto, docker, or podman." }
            $requestedEngine = $ArgsList[++$i]
        }
        "--add-folder" {
            if ($i + 1 -ge $ArgsList.Count) {
                throw "Missing folder path for --add-folder."
            }
            $addFolderArgs = @($ArgsList[($i + 1)..($ArgsList.Count - 1)])
            $i = $ArgsList.Count
        }
        default {
            if ($ArgsList[$i].StartsWith("--")) {
                throw "Unknown option: $($ArgsList[$i])"
            }
            # After the command, every argument belongs to the in-container tool.
            for ($argumentIndex = $i; $argumentIndex -lt $ArgsList.Count; $argumentIndex++) {
                $positionals.Add($ArgsList[$argumentIndex])
            }
            $i = $ArgsList.Count
        }
    }
}

if ($addFolderArgs) {
    $helper = Join-Path $RepoRoot "scripts\add-supplemental-folder.ps1"
    & $helper @addFolderArgs
    exit $LASTEXITCODE
}

$command = if ($positionals.Count -gt 0) { $positionals[0] } else { "shell" }
$commandArgs = if ($positionals.Count -gt 1) { $positionals[1..($positionals.Count - 1)] } else { @() }

$script:EngineCommand = Resolve-Engine -RequestedEngine $requestedEngine
$meta = Get-WorkspaceMeta -WorkspacePath (Get-Location).Path
$supplementalFolders = Get-SupplementalFolderMounts -WorkspacePath $meta.Workspace

if (-not (Get-ImageId -Tag $ImageTag) -or $update -or $rebuild) {
    Build-Image -Pull -Refresh:($update -or $rebuild)
}

switch ($command) {
    "stop" {
        if (Test-ContainerExists -Name $meta.Container -FailOnError) {
            Invoke-Engine stop $meta.Container | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Failed to stop container $($meta.Container) (exit code $LASTEXITCODE)." }
        }
        exit 0
    }
    "rm" {
        Remove-ContainerIfExists -Name $meta.Container
        exit 0
    }
    "reset-state" {
        Remove-ContainerIfExists -Name $meta.Container
        foreach ($volume in @($meta.ConfigVolume, $meta.AuthVolume, $meta.DataVolume, $meta.CacheVolume)) {
            Remove-VolumeIfExists -Name $volume
        }
        exit 0
    }
}

if ($rebuild) {
    Remove-ContainerIfExists -Name $meta.Container
}

Ensure-Container -Meta $meta -SupplementalFolders $supplementalFolders -ForceRecreate:$rebuild

foreach ($warning in $supplementalFolders.Warnings) {
    Write-Warning $warning
}

switch ($command) {
    "reset-config" {
        Exec-InContainer -Meta $meta -CommandArgs @("reset-config")
        break
    }
    "doctor" {
        Exec-InContainer -Meta $meta -CommandArgs @("doctor")
        break
    }
    default {
        $invokeCommand = if ($command -eq "shell") { @("shell") } else { @($command) + $commandArgs }
        $nonInteractiveCommands = @("t3", "codenomad", "paseo")
        Exec-InContainer -Meta $meta -CommandArgs $invokeCommand -Interactive:($command -notin $nonInteractiveCommands)
        break
    }
}

exit $LASTEXITCODE
