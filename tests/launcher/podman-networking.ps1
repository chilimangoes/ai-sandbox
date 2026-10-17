[CmdletBinding()]
param(
    [switch]$RunLive,
    [string]$EvidenceDirectory,
    [switch]$SkipBuild,
    [string]$Image,
    [switch]$SkipInteractive
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not $RunLive) { throw 'Native Windows networking validation requires -RunLive and an existing healthy Podman Machine.' }
if ($env:OS -ne 'Windows_NT') { throw 'Run this probe from Windows PowerShell, outside WSL.' }
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runId = 'ai-sandbox-network-' + [guid]::NewGuid().ToString('n')
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path $repoRoot ".scratch/podman-support/evidence/$runId" }
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
$null = New-Item -ItemType Directory -Force -Path $EvidenceDirectory
if ($SkipBuild -and -not $Image) { throw '-SkipBuild requires an explicitly supplied project image built by native Podman.' }
if ($Image -and -not $SkipBuild) { throw '-Image requires -SkipBuild; ordinary runs build and clean a unique image tag.' }
if (-not $Image) { $Image = "localhost/${runId}:latest" }
$ownedImage = -not $SkipBuild
$ownedContainers = New-Object 'System.Collections.Generic.List[string]'
$listeners = New-Object 'System.Collections.Generic.List[System.Net.Sockets.TcpListener]'
$commandNumber = 0
$evidence = [ordered]@{ RunId = $runId; StartedUtc = [DateTime]::UtcNow.ToString('o'); Image = $Image; CaseA = $null; CaseB = $null; InteractiveExec = $null; NonInteractiveExec = $null; Decision = $null; Result = 'in-progress'; Cleanup = @() }
$ports = @(3773, 9899, 6767, 8080, 3000)

function Invoke-Podman {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $script:commandNumber++
    $file = Join-Path $EvidenceDirectory ('command-{0:d3}.json' -f $script:commandNumber)
    $ErrorActionPreference = 'Continue'
    $output = @(& podman @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    [ordered]@{ Arguments = $Arguments; ExitCode = $exitCode; Output = $output } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $file -Encoding UTF8
    if ($exitCode -ne 0 -and -not $AllowFailure) { throw "podman $($Arguments -join ' ') failed ($exitCode): $($output -join ' ')" }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output; Evidence = [IO.Path]::GetFileName($file) }
}

function Invoke-InteractivePodman {
    param([string[]]$Arguments)
    $script:commandNumber++
    $file = Join-Path $EvidenceDirectory ('command-{0:d3}.json' -f $script:commandNumber)
    # Leave the native process attached to the caller's terminal. A pipeline or
    # redirection here would invalidate the interactive exec check.
    & podman @Arguments
    $exitCode = $LASTEXITCODE
    [ordered]@{ Arguments = $Arguments; ExitCode = $exitCode; Output = 'Inherited terminal; the command asserts stdin and stdout are TTYs before printing interactive-exec-ok.' } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $file -Encoding UTF8
    if ($exitCode -ne 0) { throw "Interactive podman exec failed ($exitCode). Run the probe in a terminal with inherited stdin and stdout." }
    $script:interactiveResult = [pscustomobject]@{ ExitCode = $exitCode; Evidence = [IO.Path]::GetFileName($file) }
}

function Get-WorkspaceHash {
    param([string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path).ToLowerInvariant()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($fullPath)) | ForEach-Object { $_.ToString('x2') }) -join '' }
    finally { $sha.Dispose() }
}

function Get-LoopbackAddress {
    param([string]$Hash)
    return '127.{0}.{1}.{2}' -f (64 + [Convert]::ToInt32($Hash.Substring(0, 2), 16) % 64), [Convert]::ToInt32($Hash.Substring(2, 2), 16), (1 + [Convert]::ToInt32($Hash.Substring(4, 2), 16) % 254)
}

function Get-BlockPorts {
    param([string]$Hash, [int]$Attempt)
    $index = ([Convert]::ToUInt32($Hash.Substring(0, 8), 16) % 6000 + $Attempt) % 6000
    $start = 20000 + 5 * $index
    return @($start, ($start + 1), ($start + 2), ($start + 3), ($start + 4))
}

function New-ExclusiveListener {
    param([string]$Address, [int]$Port)
    $listener = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Parse($Address), $Port)
    $listener.Server.ExclusiveAddressUse = $true
    try { $listener.Start(); return $listener }
    catch { $listener.Stop(); throw }
}

function Test-BlockAvailable {
    param([int[]]$HostPorts)
    $reservations = @()
    try {
        foreach ($port in $HostPorts) { $reservations += New-ExclusiveListener -Address '127.0.0.1' -Port $port }
        return $true
    } catch { return $false }
    finally { foreach ($listener in $reservations) { $listener.Stop() } }
}

function Get-Mappings {
    param([string]$Name, [string]$Address, [int[]]$HostPorts, [string]$Phase)
    $inspection = Invoke-Podman -Arguments @('inspect', $Name)
    $inspection.Output | Set-Content -LiteralPath (Join-Path $EvidenceDirectory "$Name-$Phase-inspect.json") -Encoding UTF8
    $portOutput = Invoke-Podman -Arguments @('port', $Name)
    $portOutput.Output | Set-Content -LiteralPath (Join-Path $EvidenceDirectory "$Name-$Phase-port.txt") -Encoding UTF8
    $container = ($inspection.Output -join "`n" | ConvertFrom-Json)[0]
    $endpoints = @()
    for ($index = 0; $index -lt $ports.Count; $index++) {
        $key = "$($ports[$index])/tcp"
        $mapping = @($container.NetworkSettings.Ports.$key)
        if ($mapping.Count -ne 1 -or $mapping[0].HostIp -cne $Address -or [int]$mapping[0].HostPort -ne $HostPorts[$index]) {
            throw "Actual mapping differs from requested endpoint for $Name $key`: $($mapping | ConvertTo-Json -Compress)"
        }
        $endpoints += [pscustomobject]@{ Container = $Name; ContainerPort = $ports[$index]; Address = $mapping[0].HostIp; HostPort = [int]$mapping[0].HostPort; ExpectedBody = "$Name|$($ports[$index])" }
    }
    return $endpoints
}

Add-Type -AssemblyName System.Net.Http
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.UseProxy = $false
$client = New-Object System.Net.Http.HttpClient($handler)
$client.Timeout = [TimeSpan]::FromMilliseconds(500)

function Test-Endpoints {
    param([object[]]$Endpoints, [string]$Phase)
    $checks = @($Endpoints | ForEach-Object { [pscustomobject]@{ Container = $_.Container; ContainerPort = $_.ContainerPort; Url = "http://$($_.Address):$($_.HostPort)/"; ExpectedBody = $_.ExpectedBody; Body = $null; Passed = $false; Error = $null } })
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        foreach ($check in @($checks | Where-Object { -not $_.Passed })) {
            $response = $null
            try {
                $response = $client.GetAsync($check.Url).GetAwaiter().GetResult()
                $check.Body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $check.Passed = $response.IsSuccessStatusCode -and $check.Body -ceq $check.ExpectedBody
                if ($check.Passed) { $check.Error = $null } else { $check.Error = "Status $([int]$response.StatusCode); unexpected identity." }
            } catch { $check.Error = $_.Exception.Message }
            finally { if ($response) { $response.Dispose() } }
        }
        if (@($checks | Where-Object { -not $_.Passed }).Count -eq 0) { break }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    $checks | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory "$Phase-http.json") -Encoding UTF8
    return [pscustomobject]@{ Passed = @($checks | Where-Object { -not $_.Passed }).Count -eq 0; Checks = $checks }
}

$serverCode = @'
import http.server, os, threading, time
identity = os.environ['PROBE_ID']
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = f'{identity}|{self.server.server_port}'.encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
for port in [3773, 9899, 6767, 8080, 3000]:
    server = http.server.ThreadingHTTPServer(('0.0.0.0', port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
while True:
    time.sleep(3600)
'@
$serverBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($serverCode))
$pythonCommand = "import base64;exec(base64.b64decode('$serverBase64'))"

function Start-Probe {
    param([string]$Name, [string]$Address, [int[]]$HostPorts)
    $script:ownedContainers.Add($Name)
    $arguments = @('run', '-d', '--name', $Name, '--label', "ai-sandbox.network-probe=$runId", '--env', "PROBE_ID=$Name", '--entrypoint', 'python3')
    for ($index = 0; $index -lt $ports.Count; $index++) { $arguments += @('-p', "$($Address):$($HostPorts[$index]):$($ports[$index])/tcp") }
    $arguments += @($Image, '-c', $pythonCommand)
    return Invoke-Podman -Arguments $arguments -AllowFailure
}

function Remove-OwnedProbe {
    param([string]$Name)
    if (-not $script:ownedContainers.Contains($Name)) { throw "Refusing to remove unowned container $Name." }
    $removed = Invoke-Podman -Arguments @('rm', '-f', '--time', '0', $Name) -AllowFailure
    $script:evidence.Cleanup += [ordered]@{ Resource = $Name; ExitCode = $removed.ExitCode; Command = $removed.Evidence }
    if ($removed.ExitCode -eq 0) { $null = $script:ownedContainers.Remove($Name) }
}

function Start-AllocatedProbe {
    param([string]$NamePrefix, [string]$Hash)
    $attempts = @()
    $unreachableBlocks = 0
    for ($attempt = 0; $attempt -lt 32; $attempt++) {
        $hostPorts = Get-BlockPorts -Hash $Hash -Attempt $attempt
        if (-not (Test-BlockAvailable -HostPorts $hostPorts)) {
            $attempts += [pscustomobject]@{ Attempt = $attempt; Ports = $hostPorts; Result = 'windows-bind-unavailable' }
            continue
        }
        $name = "$NamePrefix-$attempt"
        $started = Start-Probe -Name $name -Address '127.0.0.1' -HostPorts $hostPorts
        if ($started.ExitCode -ne 0) {
            $attempts += [pscustomobject]@{ Attempt = $attempt; Ports = $hostPorts; Result = 'runtime-bind-failed'; Command = $started.Evidence }
            Remove-OwnedProbe -Name $name
            if (($started.Output -join ' ') -notmatch '(?i)address already in use|port is already allocated|port.*already in use|bind.*(failed|cannot|unable)|listen tcp') {
                $attempts | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory "$NamePrefix-runtime-failure.json") -Encoding UTF8
                throw "Podman failed before endpoint validation: $($started.Output -join ' ')"
            }
            continue
        }
        $http = $null
        try {
            $endpoints = @(Get-Mappings -Name $name -Address '127.0.0.1' -HostPorts $hostPorts -Phase 'allocated')
            $http = Test-Endpoints -Endpoints $endpoints -Phase "$name-allocated"
            if (-not $http.Passed) { throw 'Windows forwarding or content identity failed.' }
            $attempts += [pscustomobject]@{ Attempt = $attempt; Ports = $hostPorts; Result = 'accepted' }
            return [pscustomobject]@{ Name = $name; Ports = $hostPorts; Endpoints = $endpoints; Attempts = $attempts }
        } catch {
            $attempts += [pscustomobject]@{ Attempt = $attempt; Ports = $hostPorts; Result = 'mapping-or-forwarding-failed'; Error = $_.Exception.Message }
            Remove-OwnedProbe -Name $name
            if ($http -and -not @($http.Checks | Where-Object { $_.Passed }).Count) {
                $unreachableBlocks++
                if ($unreachableBlocks -ge 2) {
                    $attempts | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory "$NamePrefix-forwarding-failure.json") -Encoding UTF8
                    throw 'No Windows endpoint responded correctly across two mapped Podman port blocks. Inspect Podman Machine forwarding before retrying.'
                }
            }
        }
    }
    $attempts | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory "$NamePrefix-exhaustion.json") -Encoding UTF8
    throw 'No available Podman localhost port block after 32 attempts in 20000-49999.'
}

try {
    $evidence.Windows = [Environment]::OSVersion.VersionString
    $evidence.PowerShell = $PSVersionTable.PSVersion.ToString()
    $evidence.ConnectionOverride = $env:CONTAINER_CONNECTION
    $evidence.XdgDataHome = $env:XDG_DATA_HOME
    $evidence.Version = (Invoke-Podman -Arguments @('version', '--format', 'json')).Output -join "`n" | ConvertFrom-Json
    $machineNames = @((Invoke-Podman -Arguments @('machine', 'list', '--format', '{{.Name}}')).Output | Where-Object { $_.Trim() })
    if ($machineNames.Count -eq 0) { throw 'No existing Podman Machine is available for this Windows probe.' }
    $evidence.Machines = (Invoke-Podman -Arguments (@('machine', 'inspect') + $machineNames)).Output -join "`n" | ConvertFrom-Json
    $evidence.Connections = (Invoke-Podman -Arguments @('system', 'connection', 'list', '--format', 'json')).Output -join "`n" | ConvertFrom-Json
    $evidence.Info = (Invoke-Podman -Arguments @('info', '--format', 'json')).Output -join "`n" | ConvertFrom-Json
    if (-not $SkipBuild) { $evidence.Build = (Invoke-Podman -Arguments @('build', '--pull', '-t', $Image, $repoRoot)).Evidence }
    $evidence.ImageInspect = (Invoke-Podman -Arguments @('image', 'inspect', $Image)).Evidence
    $workspaces = @(Join-Path $repoRoot 'network-probe-workspace-a'; Join-Path $repoRoot 'network-probe-workspace-b')
    $hashes = @($workspaces | ForEach-Object { Get-WorkspaceHash -Path $_ })
    $addresses = @($hashes | ForEach-Object { Get-LoopbackAddress -Hash $_ })
    for ($suffix = 1; $addresses[0] -ceq $addresses[1]; $suffix++) {
        $workspaces[1] = Join-Path $repoRoot "network-probe-workspace-b-$suffix"
        $hashes[1] = Get-WorkspaceHash -Path $workspaces[1]
        $addresses[1] = Get-LoopbackAddress -Hash $hashes[1]
    }
    $evidence.Workspaces = @($workspaces)
    $evidence.WorkspaceHashes = @($hashes)
    $caseA = [ordered]@{ Addresses = $addresses; Result = 'failed'; Initial = $null; AfterRestart = $null; Error = $null }
    $caseANames = @("$runId-a-first", "$runId-a-second")
    try {
        $endpoints = @()
        for ($index = 0; $index -lt 2; $index++) {
            $started = Start-Probe -Name $caseANames[$index] -Address $addresses[$index] -HostPorts $ports
            if ($started.ExitCode -ne 0) { throw "Case A container startup failed: $($started.Output -join ' ')" }
            $endpoints += @(Get-Mappings -Name $caseANames[$index] -Address $addresses[$index] -HostPorts $ports -Phase 'initial')
        }
        $caseA.Initial = Test-Endpoints -Endpoints $endpoints -Phase 'case-a-initial'
        foreach ($name in $caseANames) { $null = Invoke-Podman -Arguments @('restart', $name) }
        $restartedEndpoints = @()
        for ($index = 0; $index -lt 2; $index++) { $restartedEndpoints += @(Get-Mappings -Name $caseANames[$index] -Address $addresses[$index] -HostPorts $ports -Phase 'restarted') }
        $caseA.AfterRestart = Test-Endpoints -Endpoints $restartedEndpoints -Phase 'case-a-restarted'
        if ($caseA.Initial.Passed -and $caseA.AfterRestart.Passed) { $caseA.Result = 'passed' }
    } catch { $caseA.Error = $_.Exception.Message }
    $evidence.CaseA = $caseA
    if ($caseA.Result -eq 'passed') {
        $evidence.Decision = 'workspace-loopback'
        $execContainer = $caseANames[0]
    } else {
        foreach ($name in $caseANames) { if ($ownedContainers.Contains($name)) { Remove-OwnedProbe -Name $name } }
        $caseB = [ordered]@{ Range = '20000-49999'; BlockSize = 5; BlockCount = 6000; RetryLimit = 32; HashRule = 'SHA256(UTF8(lowercase(GetFullPath(workspace)))); first eight hex digits modulo 6000'; First = $null; Second = $null; ForcedCollision = $null; Initial = $null; AfterRestart = $null; Recreate = $null; Exhaustion = $null; Result = 'in-progress' }
        $evidence.CaseB = $caseB
        $candidate = Get-BlockPorts -Hash $hashes[0] -Attempt 0
        $collisionPort = @()
        foreach ($port in $candidate) {
            try { $listener = New-ExclusiveListener -Address '127.0.0.1' -Port $port; $listeners.Add($listener); $collisionPort = @($port); break } catch { }
        }
        if ($collisionPort.Count -ne 1) { throw 'Cannot create a controlled Windows collision in the first candidate block.' }
        $caseB.ForcedCollision = [ordered]@{ Address = '127.0.0.1'; Port = $collisionPort[0]; CandidateBlock = $candidate }
        $first = Start-AllocatedProbe -NamePrefix "$runId-b-first" -Hash $hashes[0]
        if ($first.Attempts[0].Result -cne 'windows-bind-unavailable' -or ($first.Ports -join ',') -ceq ($candidate -join ',')) { throw 'Forced collision did not select another complete block.' }
        $second = Start-AllocatedProbe -NamePrefix "$runId-b-second" -Hash $hashes[1]
        $caseB.First = $first
        $caseB.Second = $second
        $caseB.Initial = Test-Endpoints -Endpoints @($first.Endpoints + $second.Endpoints) -Phase 'case-b-initial'
        foreach ($name in @($first.Name, $second.Name)) { $null = Invoke-Podman -Arguments @('restart', $name) }
        $after = @(Get-Mappings -Name $first.Name -Address '127.0.0.1' -HostPorts $first.Ports -Phase 'restarted') + @(Get-Mappings -Name $second.Name -Address '127.0.0.1' -HostPorts $second.Ports -Phase 'restarted')
        $caseB.AfterRestart = Test-Endpoints -Endpoints $after -Phase 'case-b-restarted'
        Remove-OwnedProbe -Name $first.Name
        $recreated = Start-AllocatedProbe -NamePrefix "$runId-b-recreated" -Hash $hashes[0]
        # Removed forwarding sockets can remain unavailable briefly. Reapply the
        # same allocation order and advertise the inspected block that responds.
        $caseB.Recreate = [ordered]@{
            PreviousPorts = $first.Ports
            ReusedPreviousBlock = ($recreated.Ports -join ',') -ceq ($first.Ports -join ',')
            Actual = $recreated
        }
        $exhaustHash = Get-WorkspaceHash -Path (Join-Path $repoRoot "network-probe-exhaust-$runId")
        for ($attempt = 0; $attempt -lt 32; $attempt++) {
            $blocked = $false
            foreach ($port in @(Get-BlockPorts -Hash $exhaustHash -Attempt $attempt)) {
                try { $listener = New-ExclusiveListener -Address '127.0.0.1' -Port $port; $listeners.Add($listener); $blocked = $true; break } catch { }
            }
            if (-not $blocked -and (Test-BlockAvailable -HostPorts @(Get-BlockPorts -Hash $exhaustHash -Attempt $attempt))) { throw 'Exhaustion setup failed to occupy a candidate block.' }
        }
        try { $null = Start-AllocatedProbe -NamePrefix "$runId-b-exhaust" -Hash $exhaustHash; throw 'Expected bounded allocation exhaustion.' }
        catch {
            if ($_.Exception.Message -cne 'No available Podman localhost port block after 32 attempts in 20000-49999.') { throw }
            $caseB.Exhaustion = [ordered]@{ Passed = $true; Error = $_.Exception.Message; Attempts = 32 }
        }
        if (-not $caseB.Initial.Passed -or -not $caseB.AfterRestart.Passed) { throw 'Case B HTTP checks failed.' }
        $caseB.Result = 'passed'
        $evidence.CaseB = $caseB
        $evidence.Decision = 'deterministic-localhost-ports'
        $execContainer = $recreated.Name
    }
    $nonInteractive = Invoke-Podman -Arguments @('exec', $execContainer, 'sh', '-c', 'if test -t 0 || test -t 1; then exit 1; fi; printf noninteractive-exec-ok')
    if (($nonInteractive.Output -join '').Trim() -cne 'noninteractive-exec-ok') { throw 'Non-interactive exec returned unexpected output.' }
    $evidence.NonInteractiveExec = [ordered]@{ Passed = $true; Command = $nonInteractive.Evidence }
    if ($SkipInteractive) { $evidence.InteractiveExec = [ordered]@{ Passed = $false; Reason = 'Explicitly skipped; the ticket cannot pass until interactive exec is verified.' }; $evidence.Result = 'pending-interactive-exec' }
    else {
        Invoke-InteractivePodman -Arguments @('exec', '-it', $execContainer, 'sh', '-c', 'test -t 0 && test -t 1 && printf interactive-exec-ok')
        $evidence.InteractiveExec = [ordered]@{ Passed = $true; ExitCode = $script:interactiveResult.ExitCode; TtyAssertion = 'test -t 0 && test -t 1'; Command = $script:interactiveResult.Evidence }
        $evidence.Result = 'passed'
    }
} catch {
    $evidence.Result = 'failed'
    $evidence.Error = $_.Exception.Message
    if ($evidence.CaseB -and $evidence.CaseB.Result -eq 'in-progress') { $evidence.CaseB.Result = 'failed' }
    throw
}
finally {
    if ($evidence.Result -eq 'in-progress') { $evidence.Result = 'interrupted'; $evidence.Error = 'The probe was interrupted before completing required acceptance checks.' }
    foreach ($listener in $listeners) { $listener.Stop() }
    foreach ($name in $ownedContainers) {
        $removed = Invoke-Podman -Arguments @('rm', '-f', '--time', '0', $name) -AllowFailure
        $evidence.Cleanup += [ordered]@{ Resource = $name; ExitCode = $removed.ExitCode; Command = $removed.Evidence }
    }
    if ($ownedImage) {
        $removed = Invoke-Podman -Arguments @('image', 'rm', $Image) -AllowFailure
        $evidence.Cleanup += [ordered]@{ Resource = $Image; ExitCode = $removed.ExitCode; Command = $removed.Evidence }
    }
    $client.Dispose()
    $handler.Dispose()
    $evidence.FinishedUtc = [DateTime]::UtcNow.ToString('o')
    $evidence | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'result.json') -Encoding UTF8
    Write-Host "Native Podman networking result: $($evidence.Result); decision: $($evidence.Decision); evidence: $EvidenceDirectory"
}
