[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Launcher = Get-Content (Join-Path $RepoRoot "bin\ai-sandbox.ps1") -Raw
$Entrypoint = Get-Content (Join-Path $RepoRoot "docker\entrypoint.sh") -Raw

if ($Launcher -notmatch '''-v'', "\$\(\$Meta\.Workspace\):\$\(\$Meta\.ContainerWorkspacePath\)"') {
    throw "Expected PowerShell launcher to mount the repo at the resolved container workspace path."
}

if ($Launcher -notmatch '"AI_SANDBOX_WORKSPACE_PATH=\$\(\$Meta\.ContainerWorkspacePath\)"' -or
    $Launcher -notmatch '\$engineArgs \+= @\(''-e'', \$value\)') {
    throw "Expected PowerShell launcher to pass AI_SANDBOX_WORKSPACE_PATH through the selected engine."
}

if ($Entrypoint -notmatch 'WORKSPACE_PATH="\$\{AI_SANDBOX_WORKSPACE_PATH:-/workspace\}"') {
    throw "Expected entrypoint to resolve the workspace path from AI_SANDBOX_WORKSPACE_PATH."
}

if ($Entrypoint -notmatch [regex]::Escape("cd '`$WORKSPACE_PATH'")) {
    throw "Expected entrypoint to cd into the resolved workspace path."
}

Write-Host "workspace-paths.ps1 passed"
