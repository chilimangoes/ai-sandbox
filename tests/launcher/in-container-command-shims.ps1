[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dockerfile = Get-Content (Join-Path $repoRoot "Dockerfile") -Raw
$entrypoint = Get-Content (Join-Path $repoRoot "docker\entrypoint.sh") -Raw

if ($dockerfile -notmatch 'AI_SANDBOX_REAL_BIN_DIR=/opt/ai-sandbox/bin') {
    throw "Expected Dockerfile to reserve a real-binary directory for shimmed commands."
}

foreach ($command in @("codex", "agy", "copilot", "opencode", "cursor-agent", "cursor", "t3", "codenomad", "paseo")) {
    if ($dockerfile -notmatch "for command in .*${command}") {
        throw "Expected Dockerfile to install an in-container shim for $command."
    }

    $realCommand = if ($command -eq "cursor") { "cursor-agent" } else { $command }
    if ($entrypoint -notmatch "/opt/ai-sandbox/bin/${realCommand}") {
        throw "Expected docker/entrypoint.sh to call the real $command binary when dispatching $command."
    }
}

if ($dockerfile -notmatch 'exec /opt/ai-sandbox/entrypoint\.sh "\$command" "\$@"') {
    throw "Expected command shims to route back through the sandbox entrypoint."
}

Write-Host "in-container-command-shims.ps1 passed"
