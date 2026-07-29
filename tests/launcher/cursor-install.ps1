[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dockerfile = Get-Content (Join-Path $repoRoot "Dockerfile") -Raw
$entrypoint = Get-Content (Join-Path $repoRoot "docker\entrypoint.sh") -Raw
$bootstrap = Get-Content (Join-Path $repoRoot "docker\bootstrap\init-state.sh") -Raw
$usage = Get-Content (Join-Path $repoRoot "docs\usage.md") -Raw
$auth = Get-Content (Join-Path $repoRoot "docs\auth.md") -Raw

if ($dockerfile -notmatch 'curl https://cursor\.com/install -fsS \| bash') {
    throw "Expected Dockerfile to install Cursor CLI using the official installer."
}

if ($dockerfile -notmatch '(?s)command -v cursor-agent.*for command in .*cursor-agent') {
    throw "Expected Dockerfile to verify cursor-agent before creating command shims."
}

if ($dockerfile -notmatch 'AI_SANDBOX_REAL_BIN_DIR/cursor-agent') {
    throw "Expected Dockerfile to retain cursor-agent as the canonical real binary."
}

foreach ($command in @("cursor-agent", "cursor")) {
    if ($dockerfile -notmatch "for command in .*${command}") {
        throw "Expected Dockerfile to install an in-container shim for $command."
    }

    if ($entrypoint -notmatch "(?ms)${command}\).*?/opt/ai-sandbox/bin/cursor-agent") {
        throw "Expected docker/entrypoint.sh to dispatch $command to the real cursor-agent binary."
    }
}

if ($entrypoint -notmatch '(?ms)cursor\).*?/opt/ai-sandbox/bin/cursor-agent "\$@"') {
    throw "Expected the cursor alias to forward all arguments to cursor-agent."
}

if ($entrypoint -notmatch 'echo "cursor: \$\(cursor --version') {
    throw "Expected doctor output to report the Cursor CLI through the cursor alias."
}

if ($bootstrap -notmatch '/state/data/cursor') {
    throw "Expected bootstrap to create persistent Cursor state."
}

if ($bootstrap -notmatch 'ln -sfn /state/data/cursor /home/sandbox/\.cursor') {
    throw "Expected bootstrap to link Cursor home state into the data volume."
}

foreach ($name in @("cursor", "cursor-agent")) {
    if ($usage -notmatch [regex]::Escape($name)) {
        throw "Expected docs/usage.md to document $name."
    }
}

if ($auth -notmatch '/state/data/cursor') {
    throw "Expected docs/auth.md to document persisted Cursor state."
}

Write-Host "cursor-install.ps1 passed"
