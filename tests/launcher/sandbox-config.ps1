[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sandboxConfigPath = Join-Path $repoRoot "configs\shared\sandbox.config"
$entrypoint = Get-Content (Join-Path $repoRoot "docker\entrypoint.sh") -Raw

if (-not (Test-Path $sandboxConfigPath)) {
    throw "Expected configs/shared/sandbox.config to exist."
}

$sandboxConfig = Get-Content $sandboxConfigPath -Raw

if ($sandboxConfig -notmatch '(?m)^paseo_relay=0$') {
    throw "Expected configs/shared/sandbox.config to default paseo_relay=0."
}

if ($entrypoint -notmatch '/state/config/shared/sandbox\.config') {
    throw "Expected docker/entrypoint.sh to read the persisted sandbox.config file."
}

if ($entrypoint -notmatch '\$paseo_relay"\s*==\s*"1"') {
    throw "Expected docker/entrypoint.sh to opt into relay only when paseo_relay=1."
}

if ($entrypoint -notmatch '--no-relay') {
    throw "Expected docker/entrypoint.sh to pass --no-relay when Paseo relay is not enabled."
}

Write-Host "sandbox-config.ps1 passed"
