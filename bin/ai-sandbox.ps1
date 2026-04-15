[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ArgsList
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptRoot
$ImageTag = "ai-sandbox:latest"
$DefaultContainerPort = 3773
$DefaultHostPort = 3773

function Write-Usage {
    @"
Usage: ai-sandbox [--update] [--rebuild] [--t3-port <port>] [shell|codex|gemini|copilot|opencode|t3|doctor|stop|rm|reset-config|reset-state]
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
    [pscustomobject]@{
        Workspace = $fullPath
        Slug = $slug
        Hash = $suffix
        ContainerWorkspaceRoot = "/workspace"
        ContainerWorkspacePath = "/workspace/$slug"
        Container = "ai-sandbox-$slug-$suffix"
        ConfigVolume = "ai-sandbox-$slug-$suffix-config"
        AuthVolume = "ai-sandbox-$slug-$suffix-auth"
        DataVolume = "ai-sandbox-$slug-$suffix-data"
        CacheVolume = "ai-sandbox-$slug-$suffix-cache"
    }
}

function Get-FreePort {
    param([int]$StartPort)
    for ($port = $StartPort; $port -lt ($StartPort + 100); $port++) {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
        try {
            $listener.Start()
            $listener.Stop()
            return $port
        } catch {
            if ($listener) {
                try { $listener.Stop() } catch {}
            }
        }
    }
    throw "No free port found starting at $StartPort."
}

function Start-Container {
    param(
        [pscustomobject]$Meta,
        [int]$HostPort
    )

    $dockerArgs = @(
        "run", "-d",
        "--name", $Meta.Container,
        "--label", "ai-sandbox.workspace=$($Meta.Workspace)",
        "--label", "ai-sandbox.hash=$($Meta.Hash)",
        "-p", "${HostPort}:${DefaultContainerPort}",
        "-e", "AI_SANDBOX_T3_PORT=$DefaultContainerPort",
        "-e", "AI_SANDBOX_HOST_T3_PORT=$HostPort",
        "-e", "AI_SANDBOX_T3_URL=http://127.0.0.1:$HostPort",
        "-e", "AI_SANDBOX_WORKSPACE_PATH=$($Meta.ContainerWorkspacePath)",
        "-e", "LOCAL_UID=1000",
        "-e", "LOCAL_GID=1000",
        "-v", "$($Meta.Workspace):$($Meta.ContainerWorkspacePath)",
        "-v", "$($Meta.ConfigVolume):/state/config",
        "-v", "$($Meta.AuthVolume):/state/auth",
        "-v", "$($Meta.DataVolume):/state/data",
        "-v", "$($Meta.CacheVolume):/state/cache",
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
    param([string]$Name)

    try {
        $dockerCommand = Get-Command docker -ErrorAction Stop
        $dockerPath = $dockerCommand.Source
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        if ($dockerPath -match '\.(cmd|bat)$') {
            $psi.FileName = $env:ComSpec
            $psi.Arguments = "/d /c """"$dockerPath"" port $Name $DefaultContainerPort/tcp"""
        } else {
            $psi.FileName = $dockerPath
            $psi.Arguments = "port $Name $DefaultContainerPort/tcp"
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
        [int]$HostPort,
        [switch]$ForceRecreate
    )

    $currentImageId = Get-ImageId -Tag $ImageTag
    if (-not $currentImageId) {
        throw "Image $ImageTag does not exist."
    }

    if (Test-ContainerExists -Name $Meta.Container) {
        $containerImageId = Get-ContainerImageId -Name $Meta.Container
        $existingPort = Get-ExistingHostPort -Name $Meta.Container
        if ($ForceRecreate -or $containerImageId -ne $currentImageId -or ($existingPort -and $existingPort -ne $HostPort)) {
            Remove-ContainerIfExists -Name $Meta.Container
        }
    }

    Ensure-Volume -Name $Meta.ConfigVolume
    Ensure-Volume -Name $Meta.AuthVolume
    Ensure-Volume -Name $Meta.DataVolume
    Ensure-Volume -Name $Meta.CacheVolume

    if (-not (Test-ContainerExists -Name $Meta.Container)) {
        $attemptPort = $HostPort
        for ($attempt = 0; $attempt -lt 5; $attempt++) {
            try {
                Start-Container -Meta $Meta -HostPort $attemptPort
                $script:SelectedHostPort = $attemptPort
                break
            } catch {
                Remove-ContainerIfExists -Name $Meta.Container
                if ($_.Exception.Message -match 'port is already allocated' -and -not $ForceRecreate) {
                    $attemptPort = Get-FreePort -StartPort ($attemptPort + 1)
                    continue
                }
                throw
            }
        }

        if (-not (Test-ContainerExists -Name $Meta.Container)) {
            throw "Unable to start container after retrying host port selection."
        }
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
        "-e", "AI_SANDBOX_T3_URL=http://127.0.0.1:$script:SelectedHostPort",
        "-e", "AI_SANDBOX_HOST_T3_PORT=$script:SelectedHostPort",
        "-e", "AI_SANDBOX_T3_PORT=$DefaultContainerPort",
        "-e", "AI_SANDBOX_WORKSPACE_PATH=$($Meta.ContainerWorkspacePath)",
        $Meta.Container,
        "/opt/ai-sandbox/entrypoint.sh"
    )
    $dockerArgs += $CommandArgs
    & docker @dockerArgs
}

$update = $false
$rebuild = $false
$explicitPort = $null
$positionals = New-Object System.Collections.Generic.List[string]

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
        "--t3-port" {
            $i++
            if ($i -ge $ArgsList.Count) {
                throw "--t3-port requires a value."
            }
            $explicitPort = [int]$ArgsList[$i]
        }
        default {
            $positionals.Add($ArgsList[$i])
        }
    }
}

$command = if ($positionals.Count -gt 0) { $positionals[0] } else { "shell" }
$commandArgs = if ($positionals.Count -gt 1) { $positionals[1..($positionals.Count - 1)] } else { @() }

Assert-Docker
$meta = Get-WorkspaceMeta -WorkspacePath (Get-Location).Path

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

$existingPort = if (Test-ContainerExists -Name $meta.Container) { Get-ExistingHostPort -Name $meta.Container } else { $null }
$script:SelectedHostPort = if ($explicitPort) { $explicitPort } elseif ($existingPort) { $existingPort } else { Get-FreePort -StartPort $DefaultHostPort }

Ensure-Container -Meta $meta -HostPort $script:SelectedHostPort -ForceRecreate:$rebuild

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
        Exec-InContainer -Meta $meta -CommandArgs $invokeCommand -Interactive
        break
    }
}
