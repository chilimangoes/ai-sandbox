[CmdletBinding()]
param(
    [switch]$RunLive,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
if (-not $RunLive) { throw 'Coexistence acceptance requires -RunLive and two healthy native engines.' }
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$launcher = Join-Path $repoRoot 'bin/ai-sandbox.ps1'
$source = Get-Content -LiteralPath $launcher -Raw
Invoke-Expression ([regex]::Match($source, '(?ms)^function Get-WorkspaceMeta \{.*?^\}').Value)
$null = New-Item -ItemType Directory -Force -Path $EvidenceDirectory
$evidence = Join-Path (Resolve-Path $EvidenceDirectory).Path ('coexistence-' + [guid]::NewGuid().ToString('n'))
$workspace = Join-Path $evidence 'shared workspace with spaces'
$null = New-Item -ItemType Directory -Path $workspace
$meta = Get-WorkspaceMeta $workspace
$volumes = @($meta.ConfigVolume, $meta.AuthVolume, $meta.DataVolume, $meta.CacheVolume)
$decoy = $meta.Container + '-prefix-decoy'
$decoyVolumes = @($volumes | ForEach-Object { $_ + '-prefix-decoy' })
$checks = New-Object System.Collections.Generic.List[object]
$sequence = 0
$originalLocation = Get-Location
$originalEnvironment = $env:AI_SANDBOX_ENGINE
$result = [ordered]@{ Result = 'failed'; Workspace = $workspace; Checks = $checks; Connection = $env:CONTAINER_CONNECTION; XdgDataHome = $env:XDG_DATA_HOME }
$owned = @{}
$decoyIds = @{}
$decoyVolumeState = @{}

function Invoke-Runtime {
    param([string]$Engine, [string[]]$Arguments, [switch]$AllowFailure)
    $ErrorActionPreference = 'Continue'
    $output = @(& $Engine @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $script:sequence++
    [pscustomobject]@{ Engine = $Engine; Arguments = $Arguments; ExitCode = $exitCode; Output = @($output | ForEach-Object { "$_" }) } |
        ConvertTo-Json -Depth 20 | Set-Content (Join-Path $evidence ('command-{0:D4}.json' -f $script:sequence))
    if ($exitCode -ne 0 -and -not $AllowFailure) { throw "$Engine $Arguments failed ($exitCode): $output" }
    [pscustomobject]@{ ExitCode = $exitCode; Output = @($output | ForEach-Object { "$_" }) }
}
function Invoke-Launcher {
    param([string]$Engine, [string]$Command)
    $env:AI_SANDBOX_ENGINE = if ($Engine -eq 'podman') { 'docker' } else { 'podman' }
    $ErrorActionPreference = 'Continue'
    $output = @(& powershell.exe -NoProfile -File $launcher --engine $Engine $Command 2>&1)
    $exitCode = $LASTEXITCODE
    $script:sequence++
    [pscustomobject]@{ Engine = $Engine; Environment = $env:AI_SANDBOX_ENGINE; Command = $Command; ExitCode = $exitCode; Output = @($output | ForEach-Object { "$_" }) } |
        ConvertTo-Json -Depth 20 | Set-Content (Join-Path $evidence ('launcher-{0:D4}.json' -f $script:sequence))
    if ($exitCode -ne 0) { throw "Launcher --engine $Engine $Command failed ($exitCode): $output" }
}
function Read-Container {
    param([string]$Engine, [string]$Name = $meta.Container)
    @((Invoke-Runtime $Engine @('inspect', $Name)).Output -join "`n" | ConvertFrom-Json)[0]
}
function Test-Present {
    param([string]$Engine, [string]$Name, [switch]$Volume)
    $arguments = if ($Volume) { @('volume', 'ls', '--format', '{{.Name}}') } else { @('ps', '-a', '--format', '{{.Names}}') }
    @((Invoke-Runtime $Engine $arguments).Output | ForEach-Object { $_.TrimStart('/') }) -ccontains $Name
}
function Assert-Decoys {
    foreach ($engine in @('docker', 'podman')) {
        $container = Read-Container $engine $decoy
        if ($container.Id -cne $decoyIds[$engine] -or -not $container.State.Running) { throw "$engine prefix container changed or stopped." }
        foreach ($volume in $decoyVolumes) {
            if (-not (Test-Present $engine $volume -Volume)) { throw "$engine prefix volume disappeared: $volume" }
        }
        $actual = (Invoke-Runtime $engine (@('volume', 'inspect') + $decoyVolumes)).Output -join "`n"
        if ($actual -cne $decoyVolumeState[$engine]) { throw "$engine prefix volume metadata changed." }
    }
}
$manifestPython = @'
import hashlib,json,os,pathlib,stat
result={}
for kind in ('config','auth','data','cache'):
    root=pathlib.Path('/state')/kind
    entries=[]
    for directory,dirs,files in os.walk(root):
        for name in sorted(dirs+files):
            p=pathlib.Path(directory)/name;s=p.lstat()
            value={'path':str(p.relative_to(root)),'mode':stat.S_IMODE(s.st_mode),'uid':s.st_uid,'gid':s.st_gid}
            if p.is_symlink():value['link']=os.readlink(p)
            elif p.is_file():value['sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
            entries.append(value)
    result[kind]=sorted(entries,key=lambda e:e['path'])
print(json.dumps(result,sort_keys=True,separators=(',',':')))
'@
$manifestCommand = 'import base64;exec(base64.b64decode(''' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($manifestPython)) + '''))'
function Read-State {
    param([string]$Engine)
    $container = Read-Container $Engine
    $volumeState = @($volumes | ForEach-Object {
        $item = @((Invoke-Runtime $Engine @('volume', 'inspect', $_)).Output -join "`n" | ConvertFrom-Json)[0]
        [ordered]@{ Name = $item.Name; CreatedAt = $item.CreatedAt; Mountpoint = $item.Mountpoint; Driver = $item.Driver; Labels = $item.Labels; Options = $item.Options }
    })
    [ordered]@{
        Id = $container.Id; Image = $container.Image; Running = $container.State.Running
        Mounts = @($container.Mounts | Sort-Object Destination); Volumes = $volumeState
        Files = ((Invoke-Runtime $Engine @('exec', $meta.Container, 'python3', '-c', $manifestCommand)).Output -join "`n")
    } | ConvertTo-Json -Depth 40 -Compress
}
function Write-Markers {
    param([string]$Engine)
    foreach ($kind in @('config', 'auth', 'data', 'cache')) {
        $null = Invoke-Runtime $Engine @('exec', $meta.Container, 'sh', '-c', "printf '%s' '$Engine-$kind' > /state/$kind/ticket06-marker")
    }
}
function Assert-Markers {
    param([string]$Engine)
    foreach ($kind in @('config', 'auth', 'data', 'cache')) {
        if (((Invoke-Runtime $Engine @('exec', $meta.Container, 'cat', "/state/$kind/ticket06-marker")).Output -join '') -cne "$Engine-$kind") {
            throw "$Engine $kind marker crossed stores or disappeared."
        }
    }
}
try {
    Set-Location -LiteralPath $workspace
    foreach ($engine in @('docker', 'podman')) {
        $null = Invoke-Runtime $engine @('info')
        $null = Invoke-Runtime $engine @('image', 'inspect', 'ai-sandbox:latest')
        $owned[$engine] = $true
        foreach ($volume in $decoyVolumes) { $null = Invoke-Runtime $engine @('volume', 'create', $volume) }
        $null = Invoke-Runtime $engine @('run', '-d', '--name', $decoy, '--entrypoint', '/bin/sleep', 'ai-sandbox:latest', 'infinity')
        $decoyIds[$engine] = (Read-Container $engine $decoy).Id
        $decoyVolumeState[$engine] = (Invoke-Runtime $engine (@('volume', 'inspect') + $decoyVolumes)).Output -join "`n"
        foreach ($command in @('stop', 'rm', 'reset-state')) { $null = Invoke-Launcher $engine $command }
    }
    Assert-Decoys
    $checks.Add(@{ Check = 'absent-exact-resources-preserve-prefix-decoys'; Passed = $true })
    $null = Invoke-Launcher auto 'reset-config'
    if (-not (Test-Present docker $meta.Container) -or (Test-Present podman $meta.Container)) { throw 'Automatic selection did not choose Docker exclusively.' }
    $checks.Add(@{ Check = 'healthy-auto-selects-docker'; Passed = $true })
    $null = Invoke-Launcher podman 'reset-config'
    foreach ($engine in @('docker', 'podman')) { Write-Markers $engine; Assert-Markers $engine }
    if ((Read-Container docker).Id -ceq (Read-Container podman).Id) { throw 'Same workspace did not create separate containers.' }
    $checks.Add(@{ Check = 'explicit-selection-overrides-environment-four-distinct-volume-markers'; Passed = $true })
    foreach ($active in @('docker', 'podman')) {
        $peer = if ($active -eq 'docker') { 'podman' } else { 'docker' }
        $null = Invoke-Launcher $active 'reset-config'
        Write-Markers $active
        $peerState = Read-State $peer
        $peerState | Set-Content (Join-Path $evidence "$active-peer-before.json")
        foreach ($command in @('stop', 'rm', 'reset-config', 'reset-state')) {
            $null = Invoke-Launcher $active $command
            $after = Read-State $peer
            $after | Set-Content (Join-Path $evidence "$active-$command-peer-after.json")
            if ($after -cne $peerState) { throw "$active $command changed $peer container or volume contents." }
            Assert-Markers $peer
            Assert-Decoys
            if ($command -eq 'stop' -and (Read-Container $active).State.Running) { throw 'Stop left selected container running.' }
            if ($command -eq 'rm' -and (Test-Present $active $meta.Container)) { throw 'rm retained selected container.' }
            if ($command -in @('stop', 'rm', 'reset-config')) {
                foreach ($volume in $volumes) { if (-not (Test-Present $active $volume -Volume)) { throw "$command removed selected state volume." } }
            }
            if ($command -eq 'reset-config') { Assert-Markers $active }
            if ($command -eq 'reset-state') {
                if (Test-Present $active $meta.Container) { throw 'reset-state retained selected container.' }
                foreach ($volume in $volumes) { if (Test-Present $active $volume -Volume) { throw 'reset-state retained selected state volume.' } }
            }
            $checks.Add(@{ Check = 'destructive-command-isolation'; Engine = $active; Command = $command; Peer = $peer; Passed = $true })
        }
        $null = Invoke-Launcher $active 'reset-config'
        foreach ($kind in @('config', 'auth', 'data', 'cache')) {
            if ((Invoke-Runtime $active @('exec', $meta.Container, 'test', '-e', "/state/$kind/ticket06-marker") -AllowFailure).ExitCode -eq 0) { throw 'Reset state implicitly migrated an old marker.' }
        }
        Write-Markers $active
        $checks.Add(@{ Check = 'reset-state-creates-fresh-state-without-migration'; Engine = $active; Passed = $true })
    }
    $result.Result = 'passed'
} catch {
    $result.Error = "$_"
    throw
} finally {
    Set-Location -LiteralPath $originalLocation.Path
    $env:AI_SANDBOX_ENGINE = $originalEnvironment
    foreach ($engine in @('docker', 'podman')) {
        if (-not $owned[$engine]) { continue }
        foreach ($name in @($meta.Container, $decoy)) {
            if (Test-Present $engine $name) {
                if ((Invoke-Runtime $engine @('rm', '-f', $name) -AllowFailure).ExitCode -ne 0) { $result.Result = 'failed'; $result.CleanupError = "Could not remove $engine container $name" }
            }
        }
        foreach ($volume in @($volumes) + @($decoyVolumes)) {
            if (Test-Present $engine $volume -Volume) {
                if ((Invoke-Runtime $engine @('volume', 'rm', $volume) -AllowFailure).ExitCode -ne 0) { $result.Result = 'failed'; $result.CleanupError = "Could not remove $engine volume $volume" }
            }
        }
    }
    $result | ConvertTo-Json -Depth 40 | Set-Content (Join-Path $evidence 'result.json')
}
if ($result.Result -ne 'passed') { throw "Coexistence acceptance failed: $evidence" }
Write-Host "engine-coexistence-live.ps1 passed: $evidence"
