[CmdletBinding(PositionalBinding = $false)]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$SandboxArgs)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:TEST_SQL_GROUP = 'example-project-test-sql'
$env:TEST_SQL_STATE_DIR = Join-Path $HOME ".ai-sandbox/services/$env:TEST_SQL_GROUP"
$clientDirectory = Join-Path $env:TEST_SQL_STATE_DIR 'client'
[IO.Directory]::CreateDirectory($clientDirectory) | Out-Null

$deadline = [DateTime]::UtcNow.AddMinutes(10)
do {
    try {
        $lock = [IO.File]::Open((Join-Path $env:TEST_SQL_STATE_DIR 'bootstrap.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    } catch [IO.IOException] {
        if ([DateTime]::UtcNow -ge $deadline) { throw 'Timed out waiting for SQL bootstrap.' }
        Start-Sleep -Milliseconds 200
    }
} until ($lock)

try {
    $passwordFile = Join-Path $env:TEST_SQL_STATE_DIR 'server.env'
    if (-not (Test-Path -LiteralPath $passwordFile)) {
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $passwords = @(1..2 | ForEach-Object {
                $bytes = New-Object byte[] 24
                $rng.GetBytes($bytes)
                'Aa1!' + (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
            })
        } finally { $rng.Dispose() }
        [IO.File]::WriteAllText("$passwordFile.tmp", "MSSQL_SA_PASSWORD=$($passwords[0])`nTEST_SQL_PASSWORD=$($passwords[1])`n")
        Move-Item -LiteralPath "$passwordFile.tmp" -Destination $passwordFile
    }
    $passwordLine = @(Get-Content -LiteralPath $passwordFile | Where-Object { $_.StartsWith('TEST_SQL_PASSWORD=') })
    if ($passwordLine.Count -ne 1 -or $passwordLine[0] -cnotmatch '^TEST_SQL_PASSWORD=Aa1![a-f0-9]{48}$') {
        throw 'Invalid local test SQL password file.'
    }
    $connection = @{ server = 'test-sql,1433'; user = 'sandbox_test'; password = $passwordLine[0].Substring(18) }
    $connectionFile = Join-Path $clientDirectory 'connection.json'
    if (-not (Test-Path -LiteralPath $connectionFile)) {
        [IO.File]::WriteAllText("$connectionFile.tmp", ($connection | ConvertTo-Json))
        Move-Item -LiteralPath "$connectionFile.tmp" -Destination $connectionFile
    }

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $network = & docker network inspect $env:TEST_SQL_GROUP 2>&1
    $networkExists = $LASTEXITCODE -eq 0
    $ErrorActionPreference = $previousPreference
    if (-not $networkExists) {
        & docker network create $env:TEST_SQL_GROUP | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the test SQL network.' }
    }
    $composeArgs = @('compose', '--project-name', $env:TEST_SQL_GROUP, '--file', (Join-Path $PSScriptRoot 'compose.yaml'))
    & docker @composeArgs up -d --wait --wait-timeout 150 --no-recreate sql
    if ($LASTEXITCODE -ne 0) { throw 'Test SQL Server did not become ready.' }
    & docker @composeArgs run --rm -T init
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the test SQL login.' }

    $mapping = Join-Path $projectRoot '.ai-sandbox/supplemental-folders.config'
    $lines = if (Test-Path -LiteralPath $mapping) { @(Get-Content -LiteralPath $mapping) } else { @() }
    $lines = @($lines | Where-Object { $_ -notmatch '\|test-sql(\|(ro|rw))?$' })
    $lines += "$clientDirectory|test-sql|ro"
    [IO.File]::WriteAllText($mapping, (($lines -join "`n") + "`n"))
} finally { $lock.Dispose() }

Push-Location $projectRoot
try { & ai-sandbox @SandboxArgs }
finally { Pop-Location }
exit $LASTEXITCODE
