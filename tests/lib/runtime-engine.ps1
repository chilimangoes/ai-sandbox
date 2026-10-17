# Dot-source after binding -Engine. Loading this file does not change resources.
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts/lib/engine.ps1')
$script:EngineCommand = Resolve-SandboxEngine $Engine

function Invoke-TestEngine {
    # A plain function preserves native -v instead of binding PowerShell -Verbose.
    $EngineArgs = @($args)
    # Short --rm probes also need identifiable fixtures and failure cleanup.
    if ($EngineArgs[0] -eq 'run' -and $EngineArgs -notcontains '--name') {
        $name = "ai-sandbox-runtime-$script:EngineCommand-$([guid]::NewGuid().ToString('N'))"
        $runArgs = @('run', '--name', $name) + @($EngineArgs | Select-Object -Skip 1)
        try {
            Invoke-SandboxEngine -EngineArgs $runArgs
            $exitCode = $LASTEXITCODE
        } finally {
            $names = @(Invoke-SandboxEngine ps -a --format '{{.Names}}')
            if ($LASTEXITCODE -ne 0) { throw 'Could not inspect probe cleanup.' }
            if (@($names | ForEach-Object { $_.TrimStart('/') }) -contains $name) {
                Invoke-SandboxEngine rm -f $name | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'Could not remove test probe.' }
            }
        }
        $global:LASTEXITCODE = $exitCode
        return
    }
    Invoke-SandboxEngine -EngineArgs $EngineArgs
    $exitCode = $LASTEXITCODE
    if ($EngineArgs[0] -eq 'run' -and $exitCode -ne 0) {
        $index = [array]::IndexOf($EngineArgs, '--name')
        if ($index -ge 0 -and $index + 1 -lt $EngineArgs.Count) {
            $name = $EngineArgs[$index + 1]
            if (Test-TestContainerExists $name) {
                Invoke-SandboxEngine rm -f $name | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'Could not remove failed test container.' }
            }
        }
    }
    $global:LASTEXITCODE = $exitCode
}

function Test-TestContainerExists {
    param([string]$Name)
    $names = @(Invoke-TestEngine ps -a --format '{{.Names}}')
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect test cleanup.' }
    return @($names | ForEach-Object { $_.TrimStart('/') }) -contains $Name
}
