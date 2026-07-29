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
Usage: ai-sandbox [--update] [--rebuild] [--add-folder <path> [--as <name>] [--global|--local] [--read-only|--read-write] [--yes]] [shell|codex|agy|copilot|opencode|cursor|cursor-agent|t3|codenomad|paseo|doctor|stop|rm|reset-config|reset-state]
"@
}

function Assert-Docker {
    $null = Get-Command docker -ErrorAction Stop
    docker version | Out-Null
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

function Start-Container {
    param(
        [pscustomobject]$Meta,
        [pscustomobject]$SupplementalFolders
    )

    $dockerArgs = @(
        "run", "-d",
        "--name", $Meta.Container,
        "--label", "ai-sandbox.workspace=$($Meta.Workspace)",
        "--label", "ai-sandbox.hash=$($Meta.Hash)",
        "--label", "ai-sandbox.supplemental-folders=$($SupplementalFolders.Signature)",
        "-p", "$($Meta.HostAddress):${DefaultT3ContainerPort}:${DefaultT3ContainerPort}",
        "-p", "$($Meta.HostAddress):${DefaultCodeNomadContainerPort}:${DefaultCodeNomadContainerPort}",
        "-p", "$($Meta.HostAddress):${DefaultPaseoContainerPort}:${DefaultPaseoContainerPort}",
        "-p", "$($Meta.HostAddress):${DefaultAltHttpContainerPort}:${DefaultAltHttpContainerPort}",
        "-p", "$($Meta.HostAddress):${DefaultAppContainerPort}:${DefaultAppContainerPort}",
        "-e", "AI_SANDBOX_T3_PORT=$DefaultT3ContainerPort",
        "-e", "AI_SANDBOX_HOST_T3_PORT=$DefaultT3ContainerPort",
        "-e", "AI_SANDBOX_T3_URL=http://$($Meta.HostAddress):$DefaultT3ContainerPort",
        "-e", "AI_SANDBOX_CODENOMAD_PORT=$DefaultCodeNomadContainerPort",
        "-e", "AI_SANDBOX_HOST_CODENOMAD_PORT=$DefaultCodeNomadContainerPort",
        "-e", "AI_SANDBOX_CODENOMAD_URL=http://$($Meta.HostAddress):$DefaultCodeNomadContainerPort",
        "-e", "AI_SANDBOX_PASEO_PORT=$DefaultPaseoContainerPort",
        "-e", "AI_SANDBOX_HOST_PASEO_PORT=$DefaultPaseoContainerPort",
        "-e", "AI_SANDBOX_PASEO_ADDRESS=$($Meta.HostAddress):$DefaultPaseoContainerPort",
        "-e", "AI_SANDBOX_ALT_HTTP_PORT=$DefaultAltHttpContainerPort",
        "-e", "AI_SANDBOX_HOST_ALT_HTTP_PORT=$DefaultAltHttpContainerPort",
        "-e", "AI_SANDBOX_ALT_HTTP_URL=http://$($Meta.HostAddress):$DefaultAltHttpContainerPort",
        "-e", "AI_SANDBOX_APP_PORT=$DefaultAppContainerPort",
        "-e", "AI_SANDBOX_HOST_APP_PORT=$DefaultAppContainerPort",
        "-e", "AI_SANDBOX_APP_URL=http://$($Meta.HostAddress):$DefaultAppContainerPort",
        "-e", "AI_SANDBOX_WORKSPACE_PATH=$($Meta.ContainerWorkspacePath)",
        "-e", "LOCAL_UID=1000",
        "-e", "LOCAL_GID=1000",
        "-v", "$($Meta.Workspace):$($Meta.ContainerWorkspacePath)",
        "-v", "$($Meta.ConfigVolume):/state/config",
        "-v", "$($Meta.AuthVolume):/state/auth",
        "-v", "$($Meta.DataVolume):/state/data",
        "-v", "$($Meta.CacheVolume):/state/cache"
    )

    foreach ($mount in $SupplementalFolders.Mounts) {
        $dockerArgs += @("-v", "$($mount.HostPath):/supplemental/$($mount.Name):$($mount.Mode)")
    }

    $dockerArgs += @(
        $ImageTag,
        "daemon"
    )

    $output = & docker @dockerArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
        throw $message.Trim()
    }
}

function Test-ContainerExists {
    param([string]$Name)
    $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $result = docker ps -a --filter "name=^/$Name$" --format "{{.Names}}"
    } finally {
        $PSNativeCommandUseErrorActionPreference = $previousNativePreference
    }
    return $result -eq $Name
}

function Test-ContainerRunning {
    param([string]$Name)
    $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $result = docker ps --filter "name=^/$Name$" --format "{{.Names}}"
    } finally {
        $PSNativeCommandUseErrorActionPreference = $previousNativePreference
    }
    return $result -eq $Name
}

function Get-ContainerImageId {
    param([string]$Name)
    $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $value = docker inspect --format "{{.Image}}" $Name 2>$null
    } finally {
        $PSNativeCommandUseErrorActionPreference = $previousNativePreference
    }
    if ($LASTEXITCODE -ne 0) { return $null }
    return $value.Trim()
}

function Get-ContainerSupplementalFolderSignature {
    param([string]$Name)
    $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $value = docker inspect --format '{{ json .Config.Labels }}' $Name 2>$null
    } finally {
        $PSNativeCommandUseErrorActionPreference = $previousNativePreference
    }
    if ($LASTEXITCODE -ne 0) { return $null }
    $json = $value.Trim()
    if ([string]::IsNullOrWhiteSpace($json) -or $json -eq "null") { return $null }
    $labels = $json | ConvertFrom-Json
    $property = $labels.PSObject.Properties["ai-sandbox.supplemental-folders"]
    if (-not $property) { return $null }
    return "$($property.Value)"
}

function Get-ImageId {
    param([string]$Tag)
    try {
        $dockerCommand = Get-Command docker -ErrorAction Stop
        $dockerPath = $dockerCommand.Source
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        if ($dockerPath -match '\.(cmd|bat)$') {
            $psi.FileName = $env:ComSpec
            $psi.Arguments = "/d /c """"$dockerPath"" image inspect --format ""{{.Id}}"" $Tag"""
        } else {
            $psi.FileName = $dockerPath
            $psi.Arguments = "image inspect --format ""{{.Id}}"" $Tag"
        }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($psi)
        try {
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            $exitCode = $process.ExitCode
        } finally {
            $process.Dispose()
        }
    } catch {
        return $null
    }

    if ($exitCode -ne 0) { return $null }
    return $stdout.Trim()
}

function Ensure-Volume {
    param([string]$Name)

    # Use `docker volume ls` rather than `inspect` so a missing volume does not
    # emit an error on Windows PowerShell 5.1.
    $existing = docker volume ls --filter "name=^${Name}$" --format "{{.Name}}"
    if ($existing -ne $Name) {
        docker volume create $Name | Out-Null
    }
}

function Build-Image {
    param([switch]$Pull)
    $buildArgs = @("build", "-t", $ImageTag)
    if ($Pull) {
        $buildArgs += "--pull"
    }
    $buildArgs += $RepoRoot
    & docker @buildArgs
}

function Remove-ContainerIfExists {
    param([string]$Name)
    if (Test-ContainerExists -Name $Name) {
        docker rm -f $Name | Out-Null
    }
}

function Get-ExistingHostPort {
    param(
        [string]$Name,
        [int]$ContainerPort
    )

    try {
        $dockerCommand = Get-Command docker -ErrorAction Stop
        $dockerPath = $dockerCommand.Source
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        if ($dockerPath -match '\.(cmd|bat)$') {
            $psi.FileName = $env:ComSpec
            $psi.Arguments = "/d /c """"$dockerPath"" port $Name $ContainerPort/tcp"""
        } else {
            $psi.FileName = $dockerPath
            $psi.Arguments = "port $Name $ContainerPort/tcp"
        }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($psi)
        try {
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            $exitCode = $process.ExitCode
        } finally {
            $process.Dispose()
        }
    } catch {
        return $null
    }

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
    param(
        [pscustomobject]$Meta,
        [pscustomobject]$SupplementalFolders,
        [switch]$ForceRecreate
    )

    $currentImageId = Get-ImageId -Tag $ImageTag
    if (-not $currentImageId) {
        throw "Image $ImageTag does not exist."
    }

    if (Test-ContainerExists -Name $Meta.Container) {
        $containerImageId = Get-ContainerImageId -Name $Meta.Container
        $containerSupplementalSignature = Get-ContainerSupplementalFolderSignature -Name $Meta.Container
        $existingT3Port = Get-ExistingHostPort -Name $Meta.Container -ContainerPort $DefaultT3ContainerPort
        $existingCodeNomadPort = Get-ExistingHostPort -Name $Meta.Container -ContainerPort $DefaultCodeNomadContainerPort
        $existingPaseoPort = Get-ExistingHostPort -Name $Meta.Container -ContainerPort $DefaultPaseoContainerPort
        $existingAltHttpPort = Get-ExistingHostPort -Name $Meta.Container -ContainerPort $DefaultAltHttpContainerPort
        $existingAppPort = Get-ExistingHostPort -Name $Meta.Container -ContainerPort $DefaultAppContainerPort
        if ($ForceRecreate -or
            $containerImageId -ne $currentImageId -or
            $containerSupplementalSignature -ne $SupplementalFolders.Signature -or
            ($existingT3Port -and $existingT3Port -ne $DefaultT3ContainerPort) -or
            ($existingCodeNomadPort -and $existingCodeNomadPort -ne $DefaultCodeNomadContainerPort) -or
            ($existingPaseoPort -and $existingPaseoPort -ne $DefaultPaseoContainerPort) -or
            ($existingAltHttpPort -and $existingAltHttpPort -ne $DefaultAltHttpContainerPort) -or
            ($existingAppPort -and $existingAppPort -ne $DefaultAppContainerPort)) {
            Remove-ContainerIfExists -Name $Meta.Container
        }
    }

    Ensure-Volume -Name $Meta.ConfigVolume
    Ensure-Volume -Name $Meta.AuthVolume
    Ensure-Volume -Name $Meta.DataVolume
    Ensure-Volume -Name $Meta.CacheVolume

    if (-not (Test-ContainerExists -Name $Meta.Container)) {
        Start-Container -Meta $Meta -SupplementalFolders $SupplementalFolders
    } elseif (-not (Test-ContainerRunning -Name $Meta.Container)) {
        docker start $Meta.Container | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start existing container $($Meta.Container)."
        }
    }
}

function Exec-InContainer {
    param(
        [pscustomobject]$Meta,
        [string[]]$CommandArgs,
        [switch]$Interactive
    )

    $dockerArgs = @(
        if ($Interactive) {
        @("exec", "-it")
    } else {
        @("exec")
    })

    $dockerArgs += @(
        "-e", "AI_SANDBOX_T3_URL=http://$($Meta.HostAddress):$DefaultT3ContainerPort",
        "-e", "AI_SANDBOX_HOST_T3_PORT=$DefaultT3ContainerPort",
        "-e", "AI_SANDBOX_T3_PORT=$DefaultT3ContainerPort",
        "-e", "AI_SANDBOX_CODENOMAD_URL=http://$($Meta.HostAddress):$DefaultCodeNomadContainerPort",
        "-e", "AI_SANDBOX_HOST_CODENOMAD_PORT=$DefaultCodeNomadContainerPort",
        "-e", "AI_SANDBOX_CODENOMAD_PORT=$DefaultCodeNomadContainerPort",
        "-e", "AI_SANDBOX_PASEO_ADDRESS=$($Meta.HostAddress):$DefaultPaseoContainerPort",
        "-e", "AI_SANDBOX_HOST_PASEO_PORT=$DefaultPaseoContainerPort",
        "-e", "AI_SANDBOX_PASEO_PORT=$DefaultPaseoContainerPort",
        "-e", "AI_SANDBOX_ALT_HTTP_URL=http://$($Meta.HostAddress):$DefaultAltHttpContainerPort",
        "-e", "AI_SANDBOX_HOST_ALT_HTTP_PORT=$DefaultAltHttpContainerPort",
        "-e", "AI_SANDBOX_ALT_HTTP_PORT=$DefaultAltHttpContainerPort",
        "-e", "AI_SANDBOX_APP_URL=http://$($Meta.HostAddress):$DefaultAppContainerPort",
        "-e", "AI_SANDBOX_HOST_APP_PORT=$DefaultAppContainerPort",
        "-e", "AI_SANDBOX_APP_PORT=$DefaultAppContainerPort",
        "-e", "AI_SANDBOX_WORKSPACE_PATH=$($Meta.ContainerWorkspacePath)",
        $Meta.Container,
        "/opt/ai-sandbox/entrypoint.sh"
    )
    $dockerArgs += $CommandArgs
    & docker @dockerArgs
}

$update = $false
$rebuild = $false
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
            $positionals.Add($ArgsList[$i])
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

Assert-Docker
$meta = Get-WorkspaceMeta -WorkspacePath (Get-Location).Path
$supplementalFolders = Get-SupplementalFolderMounts -WorkspacePath $meta.Workspace

if (-not (Get-ImageId -Tag $ImageTag) -or $update -or $rebuild) {
    Build-Image -Pull
}

switch ($command) {
    "stop" {
        if (Test-ContainerExists -Name $meta.Container) {
            docker stop $meta.Container | Out-Null
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
            docker volume rm $volume | Out-Null 2>$null
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
