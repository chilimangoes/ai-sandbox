[CmdletBinding()]
param(
    [ValidateSet('docker', 'podman')][string]$Engine = 'podman',
    [switch]$RunLive,
    [switch]$ServicesOnly,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
)
$ErrorActionPreference = 'Stop'
if (-not $RunLive) { throw 'Native acceptance requires -RunLive.' }
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$launcher = Join-Path $repoRoot 'bin/ai-sandbox.ps1'
$source = Get-Content $launcher -Raw
foreach ($name in @('Get-WorkspaceMeta', 'Get-ServiceDefinitions', 'Get-CandidateEndpoints', 'Get-InspectedEndpoints', 'Get-EndpointEnvironment')) {
    Invoke-Expression ([regex]::Match($source, "(?ms)^function $name \{.*?^\}").Value)
}
$DefaultT3ContainerPort = 3773; $DefaultCodeNomadContainerPort = 9899; $DefaultPaseoContainerPort = 6767
$DefaultAltHttpContainerPort = 8080; $DefaultAppContainerPort = 3000
$script:EngineCommand = $Engine
$null = New-Item -ItemType Directory -Force -Path $EvidenceDirectory
$EvidenceDirectory = (Resolve-Path $EvidenceDirectory).Path
$runId = [guid]::NewGuid().ToString('n')
$root = Join-Path $EvidenceDirectory "native $Engine $runId"
$null = New-Item -ItemType Directory -Path $root
$workspaces = @((Join-Path $root 'first workspace with spaces'), (Join-Path $root 'second workspace with spaces'))
$ro = Join-Path $root 'read only folder'; $rw = Join-Path $root 'read write folder'
foreach ($path in @($ro, $rw) + $workspaces) { $null = New-Item -ItemType Directory -Path $path }
Set-Content (Join-Path $ro 'source.txt') 'read-only-source'
foreach ($workspace in $workspaces) {
    $null = New-Item -ItemType Directory -Path (Join-Path $workspace '.ai-sandbox')
    @("$ro|read only|ro", "$rw|read write|rw") | Set-Content (Join-Path $workspace '.ai-sandbox/supplemental-folders.config')
}
$metas = @($workspaces | ForEach-Object { Get-WorkspaceMeta $_ })
$processes = New-Object System.Collections.Generic.List[object]
$script:Sequence = 0
$identityTag = $null
$originalTag = $null
$checks = New-Object System.Collections.Generic.List[object]
$originalLocation = Get-Location
$result = [ordered]@{ Result = 'failed'; Engine = $Engine; RunId = $runId; ServicesOnly = [bool]$ServicesOnly; Checks = $checks; Connection = $env:CONTAINER_CONNECTION; XdgDataHome = $env:XDG_DATA_HOME }

function Invoke-Runtime {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $ErrorActionPreference = 'Continue'
    $output = @(& $Engine @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $script:Sequence++
    [pscustomobject]@{ Arguments = $Arguments; ExitCode = $exitCode; Output = @($output | ForEach-Object { "$_" }) } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $root ('command-{0:D4}.json' -f $script:Sequence))
    if ($exitCode -ne 0 -and -not $AllowFailure) { throw "$Engine $Arguments failed ($exitCode): $output" }
    [pscustomobject]@{ ExitCode = $exitCode; Output = @($output | ForEach-Object { "$_" }) }
}
function Invoke-Launcher {
    param([string]$Workspace, [string[]]$Arguments)
    Set-Location -LiteralPath $Workspace
    $ErrorActionPreference = 'Continue'
    $output = @(& powershell.exe -NoProfile -File $launcher --engine $Engine @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $script:Sequence++
    [pscustomobject]@{ Arguments = $Arguments; Workspace = $Workspace; ExitCode = $exitCode; Output = @($output | ForEach-Object { "$_" }) } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $root ('launcher-{0:D4}.json' -f $script:Sequence))
    if ($exitCode -ne 0) { throw "Launcher $Arguments failed ($exitCode): $output" }
    return @($output | ForEach-Object { "$_" })
}
function Read-Container {
    param([object]$Meta)
    $inspection = Invoke-Runtime @('inspect', $Meta.Container)
    return @(($inspection.Output -join "`n") | ConvertFrom-Json)[0]
}
function Start-Service {
    param([string]$Service)
    $stdout = Join-Path $root "$Service.stdout.txt"; $stderr = Join-Path $root "$Service.stderr.txt"
    $process = Start-Process powershell.exe -WindowStyle Hidden -PassThru -WorkingDirectory $workspaces[0] -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ArgumentList @('-NoProfile', '-File', ('"' + $launcher + '"'), '--engine', $Engine, $Service)
    $processes.Add($process)
    [pscustomobject]@{ Name = $Service; Process = $process; Stdout = $stdout; Stderr = $stderr }
}
Add-Type -AssemblyName System.Net.Http
$handler = New-Object System.Net.Http.HttpClientHandler; $handler.UseProxy = $false
$client = New-Object System.Net.Http.HttpClient($handler); $client.Timeout = [TimeSpan]::FromSeconds(2)
function Read-Http {
    param([object]$Endpoint, [string]$Path = '/', [string]$Expected = '', [object]$Service, [string]$ExpectedHostname)
    $url = "http://$($Endpoint.HostAddress):$($Endpoint.HostPort)$Path"
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if ($Service -and $Service.Process.HasExited) { throw "$($Service.Name) exited: $(Get-Content $Service.Stdout -Raw) $(Get-Content $Service.Stderr -Raw)" }
        try {
            $response = $client.GetAsync($url).GetAwaiter().GetResult()
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $status = [int]$response.StatusCode
            $response.Dispose()
            if ($status -ne 200) { throw "Wrong HTTP identity at $url`: status $status, body $body" }
            if ($Expected -and $body.Trim() -cne $Expected) { throw "Wrong HTTP identity at $url`: $body" }
            if ($Service) {
                if ($Service.Name -eq 't3' -and $body -notmatch '<title>T3 Code(?: \(Alpha\))?</title>') { throw "Wrong HTTP identity at $url`: missing T3 title" }
                if ($Service.Name -eq 'codenomad' -and $body -notmatch '<title>CodeNomad</title>') { throw "Wrong HTTP identity at $url`: missing CodeNomad title" }
                if ($Service.Name -eq 'paseo') {
                    $identity = $body | ConvertFrom-Json
                    if ($identity.status -cne 'server_info' -or $identity.hostname -cne $ExpectedHostname -or $identity.listen -cne '0.0.0.0:6767') { throw "Wrong HTTP identity at $url`: $body" }
                }
            }
            $checks.Add([pscustomobject]@{ Check = 'http'; Url = $url; Status = $status; Body = $body.Substring(0, [Math]::Min($body.Length, 4096)); Expected = $Expected; ExpectedHostname = $ExpectedHostname })
            return
        } catch {
            if ($_.Exception.Message -like 'Wrong HTTP identity*') { throw }
            Start-Sleep -Milliseconds 500
        }
    }
    throw "HTTP timeout: $url"
}
$server = @'
import base64, http.server, os, threading, time
identity=os.environ['PROBE_ID']
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body=f'{identity}|{self.server.server_port}'.encode()
        self.send_response(200);self.end_headers();self.wfile.write(body)
    def log_message(self,*args):pass
for port in map(int,os.environ['PROBE_PORTS'].split(',')):
    server=http.server.ThreadingHTTPServer(('0.0.0.0',port),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
while True:time.sleep(1)
'@
$python = 'import base64;exec(base64.b64decode(''' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($server)) + '''))'
try {
    $null = Invoke-Runtime @('version')
    foreach ($i in 0, 1) {
        $null = Invoke-Launcher $workspaces[$i] @('reset-config')
        $container = Read-Container $metas[$i]
        $metas[$i] | Add-Member Endpoints @(Get-InspectedEndpoints $container)
        if ($metas[$i].Endpoints.Count -ne 5) { throw 'Missing actual mappings.' }
    }
    $all = @($metas | ForEach-Object { $_.Endpoints } | ForEach-Object { "$($_.HostAddress):$($_.HostPort)" })
    if (@($all | Sort-Object -Unique).Count -ne 10) { throw 'Concurrent workspace endpoints collide.' }
    $checks.Add([pscustomobject]@{ Check = 'concurrent-workspaces'; Endpoints = $all })
    $first = $metas[0]
    $null = Invoke-Runtime @('exec', $first.Container, 'python3', '-c', "import pathlib; assert pathlib.Path('/supplemental/read only/source.txt').read_text().strip() == 'read-only-source'; pathlib.Path('/supplemental/read write/host-write.txt').write_text('writable')")
    $writeAttempt = Invoke-Runtime @('exec', $first.Container, 'touch', '/supplemental/read only/forbidden') -AllowFailure
    if ($writeAttempt.ExitCode -eq 0) { throw 'Read-only supplemental folder accepted a write.' }
    if ((Get-Content (Join-Path $rw 'host-write.txt') -Raw) -cne 'writable' -or (Test-Path (Join-Path $ro 'forbidden'))) { throw 'Supplemental mount mode failed.' }
    $checks.Add([pscustomobject]@{ Check = 'mount-spaces-ro-rw'; Passed = $true; Workspace = $workspaces[0]; ReadOnly = $ro; ReadWrite = $rw })

    if (-not $ServicesOnly) {
    $marker = [guid]::NewGuid().ToString('n')
    $null = Invoke-Runtime @('exec', $first.Container, 'sh', '-c', "for directory in config auth data cache; do printf '%s' '$marker' > /state/`$directory/ticket03-marker; done")
    $null = Invoke-Runtime @('exec', $first.Container, 'sh', '-c', 'printf modified > /state/config/codex/config.toml')
    $null = Invoke-Launcher $workspaces[0] @('reset-config')
    $null = Invoke-Runtime @('exec', $first.Container, 'cmp', '/state/config/codex/config.toml', '/opt/ai-sandbox/defaults/configs/codex/config.toml')
    $checks.Add([pscustomobject]@{ Check = 'reset-config-restores-preset'; Passed = $true })
    $originalId = (Read-Container $first).Id
    $null = Invoke-Launcher $workspaces[0] @('stop')
    $stoppedId = (Read-Container $first).Id
    $null = Invoke-Launcher $workspaces[0] @('reset-config')
    if ((Read-Container $first).Id -cne $originalId -or $stoppedId -cne $originalId) { throw 'Stop/start needlessly recreated a compatible container.' }
    $null = Invoke-Launcher $workspaces[0] @('rm')
    $null = Invoke-Launcher $workspaces[0] @('reset-config')
    if ((Read-Container $first).Id -ceq $originalId) { throw 'Removal did not recreate the container.' }
    foreach ($directory in @('config', 'auth', 'data', 'cache')) {
        if ((Invoke-Runtime @('exec', $first.Container, 'cat', "/state/$directory/ticket03-marker")).Output -cne $marker) { throw "Lost $directory persistence." }
    }
    $checks.Add([pscustomobject]@{ Check = 'stop-reuse-and-four-volume-recreation'; Passed = $true })

    $beforeMountChange = (Read-Container $first).Id
    Add-Content (Join-Path $workspaces[0] '.ai-sandbox/supplemental-folders.config') "$rw|second mapping|rw"
    $null = Invoke-Launcher $workspaces[0] @('reset-config')
    if ((Read-Container $first).Id -ceq $beforeMountChange) { throw 'Mount signature change did not recreate.' }
    $checks.Add([pscustomobject]@{ Check = 'mount-signature-recreation'; Passed = $true })

    $beforeEndpointChange = Read-Container $first
    $null = Invoke-Runtime @('rm', '-f', $first.Container)
    $null = Invoke-Runtime @('run', '-d', '--name', $first.Container, '--label', "ai-sandbox.supplemental-folders=$($beforeEndpointChange.Config.Labels.'ai-sandbox.supplemental-folders')", 'ai-sandbox:latest', 'daemon')
    $badId = (Read-Container $first).Id
    $null = Invoke-Launcher $workspaces[0] @('reset-config')
    $repaired = Read-Container $first
    if ($repaired.Id -ceq $badId -or @(Get-InspectedEndpoints $repaired).Count -ne 5) { throw 'Incompatible endpoint metadata was not recreated.' }
    $first.Endpoints = @(Get-InspectedEndpoints $repaired)
    $checks.Add([pscustomobject]@{ Check = 'endpoint-metadata-recreation'; Passed = $true; ActualEndpoints = $first.Endpoints })

    # A committed disposable layer changes image identity without changing mounts or ports.
    $identityTag = "ai-sandbox-ticket03-identity:$runId"
    $originalTag = "ai-sandbox-ticket03-original:$runId"
    $null = Invoke-Runtime @('commit', '--change', 'LABEL ai-sandbox.ticket03=image-identity', $first.Container, $identityTag)
    $compatibleId = (Read-Container $first).Id
    $null = Invoke-Runtime @('tag', 'ai-sandbox:latest', $originalTag)
    try {
        $null = Invoke-Runtime @('tag', $identityTag, 'ai-sandbox:latest')
        $null = Invoke-Launcher $workspaces[0] @('reset-config')
        $updated = Read-Container $first
        if ($updated.Id -ceq $compatibleId) { throw 'Image change did not recreate the compatible container.' }
        $checks.Add([pscustomobject]@{ Check = 'image-identity-recreation'; Passed = $true; OldContainer = $compatibleId; NewContainer = $updated.Id; Image = $updated.Image })
    } finally {
        $null = Invoke-Runtime @('tag', $originalTag, 'ai-sandbox:latest')
    }
    # Restore the selected image and inspect any changed host ports before services start.
    $null = Invoke-Launcher $workspaces[0] @('reset-config')
    $null = Invoke-Runtime @('image', 'rm', $identityTag, $originalTag)
    $identityTag = $null
    $originalTag = $null
    $first.Endpoints = @(Get-InspectedEndpoints (Read-Container $first))
    }

    $services = @(Start-Service 't3'; Start-Service 'codenomad'; Start-Service 'paseo')
    foreach ($service in $services) {
        $port = switch ($service.Name) { 't3' { 3773 }; 'codenomad' { 9899 }; 'paseo' { 6767 } }
        $endpoint = @($first.Endpoints | Where-Object ContainerPort -eq $port)[0]
        $httpPath = if ($service.Name -eq 'paseo') { '/api/status' } else { '/' }
        Read-Http -Endpoint $endpoint -Service $service -Path $httpPath -ExpectedHostname (Read-Container $first).Config.Hostname
        $addressPattern = [regex]::Escape("$($endpoint.HostAddress):$($endpoint.HostPort)")
        $advertisementPattern = switch ($service.Name) {
            't3' { "pairingUrl:\s+http://$addressPattern/pair#token=" }
            'codenomad' { "Local Connection URL\s*:\s*http://$addressPattern(?:\s|$)" }
            'paseo' { "(?m)^Starting Paseo on $addressPattern\r?$" }
        }
        $advertised = $false
        for ($attempt = 0; $attempt -lt 50; $attempt++) {
            if ((Get-Content $service.Stdout -Raw) -match $advertisementPattern) { $advertised = $true; break }
            Start-Sleep -Milliseconds 200
        }
        if (-not $advertised) { throw "$($service.Name) did not advertise its inspected endpoint in the expected service output." }
        $checks.Add([pscustomobject]@{ Check = 'native-service'; Service = $service.Name; Endpoint = $endpoint; AdvertisementPattern = $advertisementPattern; Stdout = $service.Stdout; Stderr = $service.Stderr; Interactive = $false })
    }
    foreach ($i in 0, 1) {
        $ports = if ($i -eq 0) { '8080,3000' } else { '3773,9899,6767,8080,3000' }
        $null = Invoke-Runtime @('exec', '-d', '-e', "PROBE_ID=$($metas[$i].Container)", '-e', "PROBE_PORTS=$ports", $metas[$i].Container, 'python3', '-c', $python)
        foreach ($endpoint in $metas[$i].Endpoints) {
            if ($i -eq 0 -and $endpoint.ContainerPort -notin @(8080,3000)) { continue }
            Read-Http $endpoint -Expected "$($metas[$i].Container)|$($endpoint.ContainerPort)"
        }
    }
    $result.Result = 'passed'
} catch {
    $result.Error = "$_"
    throw
} finally {
    $client.Dispose(); $handler.Dispose()
    Set-Location -LiteralPath $originalLocation.Path
    foreach ($meta in $metas) {
        $cleanup = Invoke-Runtime @('rm', '-f', $meta.Container) -AllowFailure
        if ($result.Result -eq 'passed' -and $cleanup.ExitCode -ne 0) { $result.Result = 'failed'; $result.Error = 'Container cleanup failed.' }
        foreach ($volume in @($meta.ConfigVolume, $meta.AuthVolume, $meta.DataVolume, $meta.CacheVolume)) {
            $cleanup = Invoke-Runtime @('volume', 'rm', $volume) -AllowFailure
            if ($result.Result -eq 'passed' -and $cleanup.ExitCode -ne 0) { $result.Result = 'failed'; $result.Error = 'Volume cleanup failed.' }
        }
    }
    foreach ($tag in @($identityTag, $originalTag)) { if ($tag) { $null = Invoke-Runtime @('image', 'rm', $tag) -AllowFailure } }
    foreach ($process in $processes) {
        if (-not $process.HasExited -and -not $process.WaitForExit(5000)) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue }
        $process.Dispose()
    }
    $result | ConvertTo-Json -Depth 16 | Set-Content (Join-Path $root 'result.json')
}
if ($result.Result -ne 'passed') { throw $result.Error }
Write-Host "podman-windows-live.ps1 passed ($Engine): $root"
