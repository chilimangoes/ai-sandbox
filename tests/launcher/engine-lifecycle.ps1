[CmdletBinding()]
param(
    [ValidateSet('docker', 'podman')][string]$Engine = 'docker',
    [switch]$RunLive,
    [switch]$Build,
    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not $RunLive) { throw 'Live validation requires -RunLive and a healthy selected engine.' }

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$launcher = Join-Path $repoRoot 'bin/ai-sandbox.ps1'
$source = Get-Content -LiteralPath $launcher -Raw
$definition = [regex]::Match($source, '(?ms)^function Get-WorkspaceMeta \{.*?^\}')
if (-not $definition.Success) { throw 'Get-WorkspaceMeta is missing.' }
Invoke-Expression $definition.Value

function Invoke-Runtime {
    param([string[]]$RuntimeArgs)
    $ErrorActionPreference = 'Continue'
    $output = & $Engine @RuntimeArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "$Engine $($RuntimeArgs -join ' ') failed: $output" }
    return $output
}

function Invoke-Launcher {
    param([string[]]$LauncherArgs)
    $ErrorActionPreference = 'Continue'
    $output = & powershell.exe -NoProfile -File $launcher --engine $Engine @LauncherArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Launcher failed: $output" }
    return $output
}

$null = Invoke-Runtime -RuntimeArgs @('version')
$taskTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$workspace = Join-Path $taskTempRoot ('ai-sandbox-live-' + [guid]::NewGuid().ToString('n') + ' with spaces')
$null = New-Item -ItemType Directory -Path $workspace
$meta = Get-WorkspaceMeta -WorkspacePath $workspace
$volumes = @($meta.ConfigVolume, $meta.AuthVolume, $meta.DataVolume, $meta.CacheVolume)
$marker = [guid]::NewGuid().ToString('n')
$originalLocation = Get-Location
$serviceProcess = $null

try {
    if ($Build) { $null = Invoke-Runtime -RuntimeArgs @('build', '--pull', '-t', 'ai-sandbox:latest', $repoRoot) }
    Set-Location -LiteralPath $workspace
    $null = Invoke-Launcher -LauncherArgs @('reset-config')
    $container = (Invoke-Runtime -RuntimeArgs @('inspect', $meta.Container) | Out-String | ConvertFrom-Json)[0]
    if (-not $container.State.Running) { throw 'First launch did not start the container.' }
    if ($container.Config.Labels.'ai-sandbox.workspace' -cne $meta.Workspace) { throw 'Workspace label changed.' }
    if ($container.Config.Labels.'ai-sandbox.hash' -cne $meta.Hash) { throw 'Workspace hash label changed.' }
    foreach ($port in @(3773, 9899, 6767, 8080, 3000)) {
        $mapping = @(Invoke-Runtime -RuntimeArgs @('port', $meta.Container, "$port/tcp"))
        if ($Engine -eq 'docker' -and $mapping -notcontains "$($meta.HostAddress):$port") {
            throw "Docker endpoint changed for port $port`: $mapping"
        }
    }
    foreach ($volume in $volumes) { $null = Invoke-Runtime -RuntimeArgs @('volume', 'inspect', $volume) }
    $null = Invoke-Runtime -RuntimeArgs @('exec', $meta.Container, 'sh', '-c', "for directory in config auth data cache; do printf '%s' '$marker' > /state/`$directory/engine-lifecycle-marker; done")
    $serviceOutput = Join-Path $workspace 'service.stdout.log'
    $serviceError = Join-Path $workspace 'service.stderr.log'
    $serviceProcess = Start-Process -FilePath powershell.exe -WindowStyle Hidden -PassThru `
        -WorkingDirectory $workspace -RedirectStandardOutput $serviceOutput -RedirectStandardError $serviceError `
        -ArgumentList @('-NoProfile', '-File', ('"' + $launcher + '"'), '--engine', $Engine, 't3')
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseProxy = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(2)
    $endpoint = @(Invoke-Runtime -RuntimeArgs @('port', $meta.Container, '3773/tcp'))[0]
    $reachable = $false
    try {
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            if ($serviceProcess.HasExited) { throw "T3 exited before startup: $(Get-Content $serviceError -Raw)" }
            try {
                $response = $client.GetAsync("http://$endpoint/").GetAwaiter().GetResult()
                $reachable = $response.IsSuccessStatusCode
                $response.Dispose()
                if ($reachable) { break }
            } catch { }
            Start-Sleep -Milliseconds 500
        }
    } finally { $client.Dispose(); $handler.Dispose() }
    if (-not $reachable) { throw "T3 was unreachable at $endpoint`: $(Get-Content $serviceOutput -Raw)" }

    $null = Invoke-Launcher -LauncherArgs @('stop')
    $null = $serviceProcess.WaitForExit(5000)
    $container = (Invoke-Runtime -RuntimeArgs @('inspect', $meta.Container) | Out-String | ConvertFrom-Json)[0]
    if ($container.State.Running) { throw 'Stop left the container running.' }
    $null = Invoke-Launcher -LauncherArgs @('rm')
    $names = @(Invoke-Runtime -RuntimeArgs @('ps', '--all', '--format', '{{.Names}}'))
    if ($names -ccontains $meta.Container) { throw 'Removal left the container present.' }
    foreach ($volume in $volumes) { $null = Invoke-Runtime -RuntimeArgs @('volume', 'inspect', $volume) }

    $null = Invoke-Launcher -LauncherArgs @('reset-config')
    foreach ($directory in @('config', 'auth', 'data', 'cache')) {
        $value = Invoke-Runtime -RuntimeArgs @('exec', $meta.Container, 'cat', "/state/$directory/engine-lifecycle-marker")
        if ($value -cne $marker) { throw "$directory state did not survive recreation." }
    }
    if ($Rebuild) {
        $null = Invoke-Launcher -LauncherArgs @('--rebuild', 'reset-config')
        foreach ($directory in @('config', 'auth', 'data', 'cache')) {
            $value = Invoke-Runtime -RuntimeArgs @('exec', $meta.Container, 'cat', "/state/$directory/engine-lifecycle-marker")
            if ($value -cne $marker) { throw "$directory state did not survive rebuild." }
        }
    }
    $null = Invoke-Launcher -LauncherArgs @('reset-state')
    $remaining = @(Invoke-Runtime -RuntimeArgs @('volume', 'ls', '--format', '{{.Name}}'))
    foreach ($volume in $volumes) {
        if ($remaining -ccontains $volume) { throw "Reset left volume $volume present." }
    }
    Write-Host "engine-lifecycle.ps1 passed ($Engine; rebuild=$Rebuild)"
} finally {
    Set-Location -LiteralPath $originalLocation.Path
    $ErrorActionPreference = 'Continue'
    & $Engine rm --force $meta.Container 2>$null | Out-Null
    if ($serviceProcess -and -not $serviceProcess.HasExited) { Stop-Process -Id $serviceProcess.Id -ErrorAction SilentlyContinue }
    if ($serviceProcess) { $serviceProcess.Dispose() }
    foreach ($volume in $volumes) { & $Engine volume rm $volume 2>$null | Out-Null }
    $resolvedWorkspace = [IO.Path]::GetFullPath($workspace)
    if (-not $resolvedWorkspace.StartsWith($taskTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing cleanup outside the temporary directory.'
    }
    Remove-Item -LiteralPath $resolvedWorkspace -Recurse -Force -ErrorAction Stop
}
