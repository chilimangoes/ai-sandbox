[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'bin/ai-sandbox.ps1') -Raw
foreach ($name in @('Get-WorkspaceMeta', 'Get-ServiceDefinitions', 'Get-CandidateEndpoints', 'Test-PortBlockAvailable', 'Get-EndpointEnvironment', 'Get-ContainerInspection', 'Get-InspectedEndpoints', 'Test-CompatibleEndpoints', 'Confirm-PublishedEndpoints', 'Get-ImageId', 'Start-Container', 'Ensure-Container', 'Exec-InContainer', 'Build-Image')) {
    $match = [regex]::Match($source, "(?ms)^function $name \{.*?^\}")
    if (-not $match.Success) { throw "Missing function $name." }
    Invoke-Expression $match.Value
}
$DefaultT3ContainerPort = 3773
$DefaultCodeNomadContainerPort = 9899
$DefaultPaseoContainerPort = 6767
$DefaultAltHttpContainerPort = 8080
$DefaultAppContainerPort = 3000
$ImageTag = 'ai-sandbox:latest'
$RepoRoot = 'D:\OneDrive\source with spaces'
$meta = Get-WorkspaceMeta 'D:\OneDrive\workspace with spaces'
$supplemental = [pscustomobject]@{ Signature = 'mount-signature'; Mounts = @([pscustomobject]@{ HostPath = 'D:\OneDrive\shared folder'; Name = 'shared folder'; Mode = 'ro' }) }

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    try { & $Action } catch { if ($_.Exception.Message -like "*$Message*") { return }; throw }
    throw "Expected failure containing: $Message"
}

$script:EngineCommand = 'docker'
$dockerEndpoints = @(Get-CandidateEndpoints $meta)
if (-not (Test-CompatibleEndpoints $meta $dockerEndpoints)) { throw 'Docker mappings were not compatible.' }
foreach ($endpoint in $dockerEndpoints) {
    if ($endpoint.HostAddress -cne $meta.HostAddress -or $endpoint.HostPort -ne $endpoint.ContainerPort) { throw 'Docker loopback contract changed.' }
}
$script:EngineCommand = 'podman'
$endpoints = @(Get-CandidateEndpoints $meta)
$hash = [Convert]::ToUInt32($meta.Hash.Substring(0, 8), 16)
if ($endpoints[0].HostPort -ne 20000 + 5 * ($hash % 6000)) { throw 'Unsigned initial block changed.' }
foreach ($attempt in @(0, 1, 31)) {
    if (-not (Test-CompatibleEndpoints $meta @(Get-CandidateEndpoints $meta $attempt))) { throw "Valid candidate $attempt was rejected." }
}
if (Test-CompatibleEndpoints $meta @(Get-CandidateEndpoints $meta 32)) { throw 'Out-of-contract block was accepted.' }
$overflow = [pscustomobject]@{ Hash = 'ffffffffffff'; HostAddress = '127.64.1.2' }
if (@(Get-CandidateEndpoints $overflow)[0].HostPort -ne 20000 + 5 * ([uint64]4294967295 % 6000)) { throw 'Signed hash overflow.' }

$listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0
$listener.Server.ExclusiveAddressUse = $true
$listener.Start()
try {
    $occupied = [pscustomobject]@{ HostAddress = '127.0.0.1'; HostPort = $listener.LocalEndpoint.Port }
    if (Test-PortBlockAvailable @($occupied)) { throw 'An occupied exclusive port was accepted.' }
} finally { $listener.Stop() }

function New-Inspection {
    param([object[]]$Mappings = $endpoints, [bool]$Running = $true)
    $ports = [ordered]@{}
    foreach ($endpoint in $Mappings) { $ports["$($endpoint.ContainerPort)/tcp"] = @([pscustomobject]@{ HostIp = $endpoint.HostAddress; HostPort = "$($endpoint.HostPort)" }) }
    [pscustomobject]@{
        Name = $meta.Container; Image = 'sha256:current-image'
        Config = [pscustomobject]@{ Labels = [pscustomobject]@{ 'ai-sandbox.supplemental-folders' = $supplemental.Signature } }
        State = [pscustomobject]@{ Running = $Running }
        NetworkSettings = [pscustomobject]@{ Ports = if ($Running) { [pscustomobject]$ports } else { $null } }
        HostConfig = [pscustomobject]@{ PortBindings = [pscustomobject]$ports }
    }
}
$script:Inspection = New-Inspection
$script:QueryFailure = $false
$script:Exists = $true
$script:ImageJson = '[{"Id":"sha256:current-image"}]'
$script:ContainerJson = $null
$script:InspectFailure = $false
$script:ImageFailure = $false
$script:Calls = New-Object System.Collections.Generic.List[object]
function Invoke-EngineQuery {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$EngineArgs)
    $script:Calls.Add(@($EngineArgs))
    if ($script:QueryFailure) { return [pscustomobject]@{ ExitCode = 125; Output = @() } }
    if (($script:InspectFailure -and $EngineArgs[0] -eq 'inspect') -or
        ($script:ImageFailure -and $EngineArgs[0] -eq 'image' -and $EngineArgs[1] -eq 'inspect')) {
        return [pscustomobject]@{ ExitCode = 125; Output = @() }
    }
    $output = switch ($EngineArgs[0]) {
        'inspect' { if ($script:ContainerJson) { $script:ContainerJson } else { ConvertTo-Json -InputObject @($script:Inspection) -Depth 12 -Compress }; break }
        'image' { if ($EngineArgs[1] -eq 'inspect') { $script:ImageJson } else { 'localhost/ai-sandbox:latest' }; break }
        'port' { $port = [int]($EngineArgs[2] -replace '/tcp$', ''); $entry = @($script:Inspection.HostConfig.PortBindings."$port/tcp")[0]; "$($entry.HostIp):$($entry.HostPort)"; break }
        default { throw "Unexpected query: $EngineArgs" }
    }
    [pscustomobject]@{ ExitCode = 0; Output = @($output) }
}
function Test-ContainerExists {
    param([string]$Name, [switch]$FailOnError)
    if ($script:QueryFailure -and $FailOnError) { throw 'Could not list containers in the selected engine.' }
    return $script:Exists
}
function Invoke-Engine {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$EngineArgs)
    $script:Calls.Add(@($EngineArgs))
    $global:LASTEXITCODE = 0
    if ($EngineArgs[0] -eq 'start') { $script:Inspection.State.Running = $true; $script:Inspection.NetworkSettings.Ports = $script:Inspection.HostConfig.PortBindings }
    if ($EngineArgs[0] -eq 'run') { $script:Inspection = New-Inspection }
}
function Ensure-Volume { param([string]$Name) $script:Calls.Add(@('volume', $Name)) }
$script:Removed = 0
function Remove-ContainerIfExists { param([string]$Name) $script:Removed++; $script:Exists = $false }

if ((Get-ImageId $ImageTag) -cne 'current-image') { throw 'Image normalization changed.' }
foreach ($malformed in @('not-json', '[]', '[{"Id":7}]', '[{"Id":""}]')) {
    $script:ImageJson = $malformed
    Assert-Throws { Get-ImageId $ImageTag } 'image inspection'
}
$script:ImageJson = '[{"Id":"sha256:current-image"}]'
$script:ImageFailure = $true
Assert-Throws { Get-ImageId $ImageTag } 'Could not inspect image'
$script:ImageFailure = $false
$script:InspectFailure = $true
Assert-Throws { Get-ContainerInspection $meta.Container } 'Could not inspect container'
$script:Exists = $false
if ($null -ne (Get-ContainerInspection $meta.Container)) { throw 'Missing container should return null.' }
$script:Exists = $true
$script:InspectFailure = $false
foreach ($malformed in @('not-json', '[]', '[{"Name":"other","Image":"x","State":{"Running":true},"Config":{}}]', '[{"Name":"' + $meta.Container + '","Image":7,"State":{"Running":true},"Config":{}}]')) {
    $script:ContainerJson = $malformed
    Assert-Throws { Get-ContainerInspection $meta.Container } 'container inspection'
}
$script:ContainerJson = $null
$script:Inspection.State.Running = 'false'
Assert-Throws { Get-ContainerInspection $meta.Container } 'container inspection'
$script:Inspection = New-Inspection
$script:QueryFailure = $true
Assert-Throws { Ensure-Container $meta $supplemental } 'Could not query images'
if ($script:Removed) { throw 'Unreachable engine caused removal.' }
$script:QueryFailure = $false

Ensure-Container $meta $supplemental
if ($script:Removed -or $meta.Endpoints.Count -ne 5) { throw 'Compatible existing mappings were not reused.' }
$script:Inspection = New-Inspection -Running $false
$script:Calls.Clear()
Ensure-Container $meta $supplemental
if ($script:Removed -or -not @($script:Calls | Where-Object { $_[0] -eq 'start' }).Count) { throw 'Stopped mappings were not reused and restarted.' }
$script:Inspection.Image = 'old-image'
Ensure-Container $meta $supplemental
if ($script:Removed -ne 1 -or $script:Inspection.Image -cne 'sha256:current-image') { throw 'Image identity change did not recreate.' }
$script:Inspection.Config.Labels.'ai-sandbox.supplemental-folders' = 'old-mounts'
Ensure-Container $meta $supplemental
if ($script:Removed -ne 2) { throw 'Mount signature change did not recreate.' }

foreach ($mutation in @('missing', 'wildcard', 'ipv6-only', 'port', 'extra')) {
    $broken = New-Inspection
    $bindings = $broken.NetworkSettings.Ports
    switch ($mutation) {
        'missing' { $bindings.PSObject.Properties.Remove('3000/tcp') }
        'wildcard' { $bindings.'3773/tcp'[0].HostIp = '0.0.0.0' }
        'ipv6-only' { $bindings.'3773/tcp'[0].HostIp = '::1' }
        'port' { $bindings.'3773/tcp'[0].HostPort = 'invalid' }
        'extra' { $bindings.'3773/tcp' += [pscustomobject]@{ HostIp = '127.0.0.2'; HostPort = '30000' } }
    }
    if (Test-CompatibleEndpoints $meta @(Get-InspectedEndpoints $broken)) { throw "Accepted incompatible $mutation mapping." }
}

$script:Calls.Clear()
Exec-InContainer $meta @('t3', '--help', 'value with spaces', 'D:\OneDrive\folder with spaces')
$exec = $script:Calls[$script:Calls.Count - 1]
if ($exec -contains '-it') { throw 'Noninteractive exec acquired a TTY.' }
if (($exec[($exec.Count - 4)..($exec.Count - 1)] -join '|') -cne 't3|--help|value with spaces|D:\OneDrive\folder with spaces') { throw 'Exec arguments changed.' }
foreach ($endpoint in $endpoints) {
    if (-not @($exec | Where-Object { $_ -like "AI_SANDBOX_HOST_*_PORT=$($endpoint.HostPort)" }).Count) { throw 'Exec did not advertise actual inspected host ports.' }
}
Exec-InContainer $meta @('shell') -Interactive
if ($script:Calls[$script:Calls.Count - 1] -notcontains '-it') { throw 'Interactive exec lost its TTY.' }
Build-Image -Pull -Refresh
$build = $script:Calls[$script:Calls.Count - 1]
if ($build -notcontains '--pull=always' -or $build -notcontains '--no-cache' -or $build[-1] -cne $RepoRoot) { throw 'Native Podman build flags or spaced context changed.' }

# Replace only the OS reservation boundary to exercise all bounded allocation paths.
$script:Reservations = 0
function Test-PortBlockAvailable { param([object[]]$Endpoints) $script:Reservations++; return $false }
$script:Calls.Clear()
Assert-Throws { Start-Container $meta $supplemental } 'No available Podman localhost port block after 32 attempts in 20000-49999.'
if ($script:Reservations -ne 32 -or $script:Calls.Count) { throw 'Exhaustion was not bounded before native creation.' }
function Test-PortBlockAvailable { param([object[]]$Endpoints) return $true }
$script:Runs = 0
$script:Race = $true
function Invoke-Engine {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$EngineArgs)
    $script:Calls.Add(@($EngineArgs))
    $script:Runs++
    if ($script:Runs -eq 1) {
        $global:LASTEXITCODE = 125
        if ($script:Race) { 'bind: address already in use' } else { 'OCI runtime permission denied' }
    } else { $global:LASTEXITCODE = 0 }
}
Start-Container $meta $supplemental
if ($script:Runs -ne 2 -or $script:Calls[-1] -notcontains "127.0.0.1:$($endpoints[0].HostPort + 5):3773") { throw 'Native bind race did not select the next block.' }
$script:Runs = 0
$script:Race = $false
Assert-Throws { Start-Container $meta $supplemental } 'OCI runtime permission denied'
if ($script:Runs -ne 1) { throw 'Unrelated runtime error was retried.' }
Write-Host 'podman-windows.ps1 passed'
