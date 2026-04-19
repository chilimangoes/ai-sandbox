[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$entrypoint = Get-Content (Join-Path $repoRoot "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 'ensure_paseo_workspace_registry\(\)') {
    throw "Expected docker/entrypoint.sh to define a Paseo workspace registry bootstrap helper."
}

if ($entrypoint -notmatch 'projectsDir = path\.join\(paseoHome, "projects"\)' -or $entrypoint -notmatch 'workspacesPath = path\.join\(projectsDir, "workspaces\.json"\)') {
    throw "Expected the Paseo helper to write the workspace registry under PASEO_HOME/projects/workspaces.json."
}

if ($entrypoint -notmatch 'projectsPath = path\.join\(projectsDir, "projects\.json"\)') {
    throw "Expected the Paseo helper to write the project registry under PASEO_HOME/projects/projects.json."
}

if ($entrypoint -notmatch 'AI_SANDBOX_WORKSPACE_PATH') {
    throw "Expected the Paseo helper to register the sandbox workspace path."
}

if ($entrypoint -notmatch 'export PASEO_HOME=/state/data/paseo; ensure_paseo_workspace_registry; export PASEO_LISTEN=') {
    throw "Expected run_paseo to update the Paseo workspace registry before starting the daemon."
}

Write-Host "paseo-workspace-registry.ps1 passed"
