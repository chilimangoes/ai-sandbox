[CmdletBinding(PositionalBinding = $false)]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$SandboxArgs)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:TEST_SQL_GROUP = 'example-project-test-sql'
$env:TEST_SQL_STATE_DIR = Join-Path $projectRoot '.local/test-sql'
$image = 'mcr.microsoft.com/mssql/server:2022-CU22-GDR1-ubuntu-22.04'

function Invoke-Docker([string[]]$Arguments) {
    # Docker progress on stderr is ordinary output in Windows PowerShell.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & docker @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw "Docker $($Arguments[0]) failed. Check Docker Desktop/Engine and the test service status." }
    $output -join "`n"
}

function Get-SqlContainer {
    $id = Invoke-Docker @('container', 'ls', '-aq', '--filter', "label=com.docker.compose.project=$env:TEST_SQL_GROUP", '--filter', 'label=com.docker.compose.service=sql')
    if ($id -match "`n") { throw 'Multiple SQL containers found for the service group.' }
    if ($id) { return @(ConvertFrom-Json (Invoke-Docker @('container', 'inspect', $id)))[0] }
}

$container = Get-SqlContainer
if ($container) { $lockImage = $container.Image }
else {
    if (-not (Invoke-Docker @('image', 'ls', '-q', $image))) { Invoke-Docker @('pull', $image) | Out-Null }
    $lockImage = $image
}

# The daemon-wide helper expires after ten minutes if the bootstrap exits unexpectedly.
$lockId = $null
$deadline = [DateTime]::UtcNow.AddSeconds(660)
$missingHolderFailures = 0
try {
    while (-not $lockId) {
        try {
            $lockId = Invoke-Docker @('run', '-d', '--rm', '--name', "$env:TEST_SQL_GROUP-bootstrap-lock", '--label', "ai-sandbox.shared-sql=$env:TEST_SQL_GROUP", '--entrypoint', '/bin/sleep', $lockImage, '600')
        } catch {
            $holder = Invoke-Docker @('container', 'ls', '-aq', '--filter', "name=^/$env:TEST_SQL_GROUP-bootstrap-lock`$")
            if ($holder) {
                # The holder can finish between listing and inspecting its helper.
                $details = $null
                try { $details = @(ConvertFrom-Json (Invoke-Docker @('container', 'inspect', $holder)))[0] }
                catch {
                    $remaining = Invoke-Docker @('container', 'ls', '-aq', '--filter', "name=^/$env:TEST_SQL_GROUP-bootstrap-lock`$")
                    if ($remaining -eq $holder) { throw }
                }
                if ($details -and $details.Config.Labels.'ai-sandbox.shared-sql' -cne $env:TEST_SQL_GROUP) { throw 'Bootstrap lock name belongs to another service.' }
                $missingHolderFailures = 0
            } else {
                $missingHolderFailures++
                if ($missingHolderFailures -ge 2) { throw }
            }
            if ([DateTime]::UtcNow -ge $deadline) { throw 'Timed out waiting for SQL bootstrap.' }
            Start-Sleep -Seconds 1
        }
    }
    $container = Get-SqlContainer
    $passwordFile = Join-Path $env:TEST_SQL_STATE_DIR 'server.env'
    if ($container) { $lines = $container.Config.Env }
    elseif (Test-Path -LiteralPath $passwordFile) { $lines = Get-Content -LiteralPath $passwordFile }
    else {
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $passwords = @(1..2 | ForEach-Object {
                $bytes = New-Object byte[] 24
                $rng.GetBytes($bytes)
                'Aa1!' + (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
            })
        } finally { $rng.Dispose() }
        $lines = @("MSSQL_SA_PASSWORD=$($passwords[0])", "TEST_SQL_PASSWORD=$($passwords[1])")
    }
    $values = @{}
    foreach ($line in $lines) {
        if ($line -cmatch '^(MSSQL_SA_PASSWORD|TEST_SQL_PASSWORD)=(.*)$') {
            if ($values.ContainsKey($Matches[1])) { throw 'Duplicate SQL password entry.' }
            $values[$Matches[1]] = $Matches[2]
        }
    }
    foreach ($key in @('MSSQL_SA_PASSWORD', 'TEST_SQL_PASSWORD')) {
        if ($values[$key] -cnotmatch '^Aa1![a-f0-9]{48}$') { throw 'Invalid generated test SQL credentials. Local state was not updated.' }
    }
    $clientDirectory = Join-Path $env:TEST_SQL_STATE_DIR 'client'
    [IO.Directory]::CreateDirectory($clientDirectory) | Out-Null
    $connectionFile = Join-Path $clientDirectory 'connection.json'
    $connection = @{ server = 'test-sql,1433'; user = 'sandbox_test'; password = $values['TEST_SQL_PASSWORD'] }
    [IO.File]::WriteAllText("$passwordFile.tmp", "MSSQL_SA_PASSWORD=$($values['MSSQL_SA_PASSWORD'])`nTEST_SQL_PASSWORD=$($values['TEST_SQL_PASSWORD'])`n")
    Move-Item -LiteralPath "$passwordFile.tmp" -Destination $passwordFile -Force
    [IO.File]::WriteAllText("$connectionFile.tmp", ($connection | ConvertTo-Json))
    Move-Item -LiteralPath "$connectionFile.tmp" -Destination $connectionFile -Force

    $network = Invoke-Docker @('network', 'ls', '-q', '--filter', "name=^$env:TEST_SQL_GROUP`$")
    if (-not $network) { Invoke-Docker @('network', 'create', $env:TEST_SQL_GROUP) | Out-Null }
    $compose = @('compose', '--project-name', $env:TEST_SQL_GROUP, '--file', (Join-Path $PSScriptRoot 'compose.yaml'))
    Write-Host "Waiting for $env:TEST_SQL_GROUP and verifying the test login..."
    Invoke-Docker ($compose + @('up', '-d', '--wait', '--wait-timeout', '150', '--no-recreate', 'sql')) | Out-Null
    Invoke-Docker ($compose + @('run', '--rm', '-T', 'init')) | Out-Null
} finally {
    if ($lockId) {
        try { Invoke-Docker @('rm', '-f', $lockId) | Out-Null }
        catch { Write-Warning 'Could not release SQL bootstrap lock; Docker will expire it automatically.' }
    }
}

Push-Location $projectRoot
try { & ai-sandbox @SandboxArgs }
finally { Pop-Location }
exit $LASTEXITCODE
