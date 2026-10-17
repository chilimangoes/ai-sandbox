# Operational helpers share the launchers' CLI > environment > auto policy.
function Get-SandboxOptions {
    param([string]$Engine, [string[]]$Arguments, [switch]$AllowNoCache, [switch]$AllowSkipBuild)
    $options = @{ Engine = $Engine; NoCache = $false; SkipBuild = $false }
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        switch -CaseSensitive ($Arguments[$i]) {
            '--engine' {
                if ($i + 1 -ge $Arguments.Count) { throw 'Missing engine for --engine.' }
                $options.Engine = $Arguments[++$i]
            }
            '--no-cache' { if (-not $AllowNoCache) { throw 'Unexpected --no-cache.' }; $options.NoCache = $true }
            '--skip-build' { if (-not $AllowSkipBuild) { throw 'Unexpected --skip-build.' }; $options.SkipBuild = $true }
            default { throw "Unknown option: $($Arguments[$i])" }
        }
    }
    return [pscustomobject]$options
}

function Invoke-SandboxEngine {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$EngineArgs)
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    & $script:EngineCommand @EngineArgs
}

function Get-SandboxEngineStatus {
    param([string]$Name)
    $status = [ordered]@{ Engine = $Name; Client = 'missing'; Server = 'unavailable'; Ready = $false }
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { return [pscustomobject]$status }
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $client = & $Name --version 2>$null
        $status.Client = ($client -join ' ').Trim()
        if (-not $status.Client) { $status.Client = 'unavailable' }
        $version = & $Name version --format '{{json .}}' 2>$null
        if ($LASTEXITCODE -eq 0) {
            $parsed = ($version -join "`n") | ConvertFrom-Json -ErrorAction Stop
            if ($parsed.Client.Version) { $status.Client = $parsed.Client.Version }
            if ($parsed.Server.Version) { $status.Server = $parsed.Server.Version; $status.Ready = $true }
            if ($Name -eq 'podman') {
                # Local Podman has no server. info also proves storage/runtime readiness.
                $status.Ready = $false
                $info = & $Name info --format=json 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $hostInfo = ($info -join "`n") | ConvertFrom-Json -ErrorAction Stop
                    if ($hostInfo.Host.serviceIsRemote -eq $false) {
                        $status.Server = "not applicable (local Podman engine $($status.Client))"
                        $status.Ready = $true
                    } elseif ($hostInfo.Host.serviceIsRemote -eq $true -and $parsed.Server.Version) {
                        $status.Ready = $true
                    }
                }
            }
        }
    } catch { }
    return [pscustomobject]$status
}

function Resolve-SandboxEngine {
    param([string]$RequestedEngine)
    if ($RequestedEngine -cnotin @('auto', 'docker', 'podman')) {
        throw "Invalid engine '$RequestedEngine'. Expected auto, docker, or podman."
    }
    $candidates = if ($RequestedEngine -ceq 'auto') { @('docker', 'podman') } else { @($RequestedEngine) }
    foreach ($candidate in $candidates) {
        if ((Get-SandboxEngineStatus $candidate).Ready) { return $candidate }
    }
    $guidance = ' Inspect Podman with `podman machine list` and `podman system connection list`; start the intended stopped machine with `podman machine start <name>`.'
    if ($RequestedEngine -ceq 'auto') { throw "No healthy container engine is available. Start Docker.$guidance" }
    $status = Get-SandboxEngineStatus $RequestedEngine
    $reason = if ($status.Client -eq 'missing') { 'client is missing' } else { 'server is unreachable or unhealthy' }
    if ($RequestedEngine -cne 'podman') { $guidance = '' }
    throw "Selected engine '$RequestedEngine' $reason.$guidance"
}
